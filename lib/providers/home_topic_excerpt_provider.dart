import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/topic.dart';
import 'discourse_providers.dart';
import 'preferences_provider.dart';
import 'theme_provider.dart';

typedef TopicPreviewFetcher = Future<TopicDetail?> Function(int topicId);

final homeTopicExcerptPausedProvider = StateProvider<bool>((ref) => false);

final homeTopicExcerptLoaderProvider = Provider<HomeTopicExcerptLoader>((ref) {
  final batchSize = ref.watch(
    preferencesProvider.select(resolveHomeExcerptBatchSize),
  );
  final persistentCache = HomeTopicExcerptPersistentCache(
    ref.watch(sharedPreferencesProvider),
  );
  unawaited(
    persistentCache.pruneExpired(HomeTopicExcerptLoader.defaultCacheTtl),
  );
  final loader = HomeTopicExcerptLoader(
    maxConcurrentRequests: batchSize,
    persistentCache: persistentCache,
    fetchPreview: (topicId) => ref
        .read(discourseServiceProvider)
        .getTopicFirstPostPreviewDetail(topicId, background: true),
  );
  ref.onDispose(loader.dispose);
  return loader;
});

final homeTopicExcerptProvider = FutureProvider.autoDispose
    .family<String?, int>((ref, topicId) async {
      return ref.watch(homeTopicExcerptLoaderProvider).load(topicId);
    });

@visibleForTesting
int resolveHomeExcerptBatchSize(AppPreferences preferences) {
  final foregroundHeadroom = preferences.maxConcurrent > 1
      ? preferences.maxConcurrent - 1
      : 1;
  return preferences.homeExcerptBatchSize > foregroundHeadroom
      ? foregroundHeadroom
      : preferences.homeExcerptBatchSize;
}

class HomeTopicExcerptLoader {
  static const defaultCacheTtl = Duration(days: 1);

  HomeTopicExcerptLoader({
    required TopicPreviewFetcher fetchPreview,
    int maxCacheEntries = 160,
    int maxPreviewEntries = 24,
    Duration cacheTtl = defaultCacheTtl,
    int maxConcurrentRequests = 3,
    Duration minRequestInterval = const Duration(milliseconds: 120),
    Duration failureCooldown = const Duration(seconds: 45),
    Duration requestTimeout = const Duration(seconds: 8),
    HomeTopicExcerptPersistentCache? persistentCache,
  }) : _fetchPreview = fetchPreview,
       _maxCacheEntries = maxCacheEntries,
       _maxPreviewEntries = maxPreviewEntries,
       _cacheTtl = cacheTtl,
       _maxConcurrentRequests = maxConcurrentRequests.clamp(1, 8).toInt(),
       _minRequestInterval = minRequestInterval,
       _failureCooldown = failureCooldown,
       _requestTimeout = requestTimeout,
       _persistentCache = persistentCache;

  final TopicPreviewFetcher _fetchPreview;
  final int _maxCacheEntries;
  final int _maxPreviewEntries;
  final Duration _cacheTtl;
  final int _maxConcurrentRequests;
  final Duration _minRequestInterval;
  final Duration _failureCooldown;
  final Duration _requestTimeout;
  final HomeTopicExcerptPersistentCache? _persistentCache;

  final _cache = <int, _CachedExcerpt>{};
  final _previewCache = <int, _CachedPreviewDetail>{};
  final _inFlight = <int, Future<String?>>{};
  final _failureUntil = <int, DateTime>{};
  final _pendingQueue = Queue<_QueuedExcerpt>();

  Future<void> _startSlotTail = Future<void>.value();
  DateTime? _lastRequestStartedAt;
  int _activeRequests = 0;
  bool _paused = false;
  bool _disposed = false;

  String? peekCached(int topicId) {
    if (_disposed) return null;
    return _readCache(topicId);
  }

  TopicDetail? peekCachedPreview(int topicId) {
    if (_disposed) return null;

    final entry = _previewCache.remove(topicId);
    if (entry == null) return null;
    if (DateTime.now().difference(entry.createdAt) > _cacheTtl) {
      return null;
    }

    _previewCache[topicId] = entry;
    return entry.detail;
  }

  Future<int> warmupTopics(Iterable<int> topicIds, {int maxTopics = 8}) async {
    if (_disposed) return 0;

    final seen = <int>{};
    final deduped = <int>[];
    for (final topicId in topicIds) {
      if (topicId <= 0 || !seen.add(topicId)) continue;
      deduped.add(topicId);
      if (deduped.length >= maxTopics) break;
    }
    if (deduped.isEmpty) return 0;

    final results = await Future.wait(deduped.map(load));
    return results
        .where((html) => html != null && html.trim().isNotEmpty)
        .length;
  }

  Future<String?> load(int topicId) {
    if (_disposed) return Future.value(null);

    final cached = _readCache(topicId);
    if (cached != null) return Future.value(cached);

    final now = DateTime.now();
    final failureUntil = _failureUntil[topicId];
    if (failureUntil != null) {
      if (failureUntil.isAfter(now)) return Future.value(null);
      _failureUntil.remove(topicId);
    }

    final existing = _inFlight[topicId];
    if (existing != null) return existing;

    final completer = Completer<String?>();
    final future = completer.future.whenComplete(() {
      _inFlight.remove(topicId);
    });
    _inFlight[topicId] = future;

    _pendingQueue.add(_QueuedExcerpt(topicId, completer));
    _pumpQueue();

    return future;
  }

  void dispose() {
    _disposed = true;
    _cancelPendingRequests();
    _cache.clear();
    _previewCache.clear();
    _inFlight.clear();
    _failureUntil.clear();
  }

  void setPaused(bool paused) {
    if (_disposed || _paused == paused) return;
    _paused = paused;
    if (!paused) {
      _pumpQueue();
    }
  }

  void _cancelPendingRequests() {
    for (final queued in _pendingQueue) {
      _inFlight.remove(queued.topicId);
      _completeIfNeeded(queued.completer, null);
    }
    _pendingQueue.clear();
  }

  void _pumpQueue() {
    if (_disposed) return;
    if (_paused) return;

    while (_activeRequests < _maxConcurrentRequests &&
        _pendingQueue.isNotEmpty) {
      final queued = _pendingQueue.removeFirst();
      _activeRequests++;
      unawaited(
        _runQueued(queued.topicId, queued.completer).whenComplete(() {
          _activeRequests--;
          _pumpQueue();
        }),
      );
    }
  }

  Future<void> _runQueued(int topicId, Completer<String?> completer) async {
    if (_disposed) {
      _completeIfNeeded(completer, null);
      return;
    }

    final cached = _readCache(topicId);
    if (cached != null) {
      _completeIfNeeded(completer, cached);
      return;
    }

    final now = DateTime.now();
    final failureUntil = _failureUntil[topicId];
    if (failureUntil != null && failureUntil.isAfter(now)) {
      _completeIfNeeded(completer, null);
      return;
    }

    await _reserveRequestStartSlot();
    if (_disposed) {
      _completeIfNeeded(completer, null);
      return;
    }

    try {
      final preview = await _fetchPreview(topicId).timeout(_requestTimeout);
      final excerpt = preview?.postStream.posts.firstOrNull?.cooked;
      if (preview != null && excerpt != null && excerpt.trim().isNotEmpty) {
        _writeCache(topicId, excerpt, preview: preview);
      }
      _completeIfNeeded(completer, excerpt);
    } catch (_) {
      _failureUntil[topicId] = DateTime.now().add(_failureCooldown);
      _completeIfNeeded(completer, null);
    }
  }

  Future<void> _reserveRequestStartSlot() {
    final slot = _startSlotTail.then((_) async {
      final lastStarted = _lastRequestStartedAt;
      if (lastStarted != null && _minRequestInterval > Duration.zero) {
        final elapsed = DateTime.now().difference(lastStarted);
        final remaining = _minRequestInterval - elapsed;
        if (remaining > Duration.zero) {
          await Future<void>.delayed(remaining);
        }
      }
      _lastRequestStartedAt = DateTime.now();
    });
    _startSlotTail = slot.catchError((_) {});
    return slot;
  }

  String? _readCache(int topicId) {
    final entry = _cache.remove(topicId);
    if (entry != null) {
      if (DateTime.now().difference(entry.createdAt) <= _cacheTtl) {
        _cache[topicId] = entry;
        return entry.excerpt;
      }
    }

    final persistent = _persistentCache?.read(topicId, _cacheTtl);
    if (persistent == null) return null;

    _writeMemoryCache(topicId, persistent);
    return persistent;
  }

  void _writeCache(int topicId, String excerpt, {TopicDetail? preview}) {
    _writeMemoryCache(topicId, excerpt);
    if (preview != null) {
      _writePreviewCache(topicId, preview);
    }
    unawaited(_persistentCache?.write(topicId, excerpt, _cacheTtl));
  }

  void _writeMemoryCache(int topicId, String excerpt) {
    _cache.remove(topicId);
    _cache[topicId] = _CachedExcerpt(excerpt, DateTime.now());
    while (_cache.length > _maxCacheEntries) {
      final evictedTopicId = _cache.keys.first;
      _cache.remove(evictedTopicId);
      _previewCache.remove(evictedTopicId);
    }
  }

  void _writePreviewCache(int topicId, TopicDetail detail) {
    _previewCache.remove(topicId);
    _previewCache[topicId] = _CachedPreviewDetail(detail, DateTime.now());
    while (_previewCache.length > _maxPreviewEntries) {
      _previewCache.remove(_previewCache.keys.first);
    }
  }

  void _completeIfNeeded(Completer<String?> completer, String? value) {
    if (!completer.isCompleted) completer.complete(value);
  }
}

class HomeTopicExcerptPersistentCache {
  HomeTopicExcerptPersistentCache(
    this._prefs, {
    this.maxEntries = 240,
    this.persistDebounce = const Duration(milliseconds: 400),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const storageKey = 'home_topic_excerpt_cache_v1';

  final SharedPreferences _prefs;
  final int maxEntries;
  final Duration persistDebounce;
  final DateTime Function() _now;

  Map<int, _PersistedExcerpt>? _entries;
  Timer? _persistTimer;

  String? read(int topicId, Duration ttl) {
    final entries = _loadEntries();
    final entry = entries.remove(topicId);
    if (entry == null) return null;

    if (_isExpired(entry.cachedAtMillis, ttl)) {
      unawaited(_schedulePersist(entries));
      return null;
    }

    entries[topicId] = entry;
    return entry.excerpt;
  }

  Future<void> write(int topicId, String excerpt, Duration ttl) async {
    final entries = _loadEntries();
    _pruneExpiredEntries(entries, ttl);
    entries.remove(topicId);
    entries[topicId] = _PersistedExcerpt(
      excerpt,
      _now().millisecondsSinceEpoch,
    );
    while (entries.length > maxEntries) {
      entries.remove(entries.keys.first);
    }
    await _schedulePersist(entries);
  }

  Future<void> pruneExpired(Duration ttl) async {
    final entries = _loadEntries();
    final changed = _pruneExpiredEntries(entries, ttl);
    if (changed) {
      await _schedulePersist(entries);
    }
  }

  Map<int, _PersistedExcerpt> _loadEntries() {
    final cached = _entries;
    if (cached != null) return cached;

    final raw = _prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      return _entries = <int, _PersistedExcerpt>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return _entries = <int, _PersistedExcerpt>{};

      final entries = <int, _PersistedExcerpt>{};
      for (final item in decoded.entries) {
        final topicId = int.tryParse(item.key.toString());
        final value = item.value;
        if (topicId == null || value is! Map) continue;
        final excerpt = value['excerpt'];
        final cachedAt = value['cachedAt'];
        if (excerpt is! String || cachedAt is! num) continue;
        entries[topicId] = _PersistedExcerpt(excerpt, cachedAt.toInt());
      }
      return _entries = entries;
    } catch (_) {
      unawaited(_prefs.remove(storageKey));
      return _entries = <int, _PersistedExcerpt>{};
    }
  }

  bool _pruneExpiredEntries(Map<int, _PersistedExcerpt> entries, Duration ttl) {
    var changed = false;
    for (final entry in entries.entries.toList()) {
      if (_isExpired(entry.value.cachedAtMillis, ttl)) {
        entries.remove(entry.key);
        changed = true;
      }
    }
    return changed;
  }

  bool _isExpired(int cachedAtMillis, Duration ttl) {
    final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMillis);
    return _now().difference(cachedAt) > ttl;
  }

  Future<void> _persist(Map<int, _PersistedExcerpt> entries) {
    if (entries.isEmpty) {
      return _prefs.remove(storageKey);
    }

    final json = <String, Map<String, dynamic>>{
      for (final entry in entries.entries)
        '${entry.key}': {
          'excerpt': entry.value.excerpt,
          'cachedAt': entry.value.cachedAtMillis,
        },
    };
    return _prefs.setString(storageKey, jsonEncode(json));
  }

  Future<void> _schedulePersist(Map<int, _PersistedExcerpt> entries) async {
    _persistTimer?.cancel();

    if (persistDebounce == Duration.zero) {
      await _persist(entries);
      return;
    }

    _persistTimer = Timer(persistDebounce, () {
      unawaited(_persist(entries));
    });
  }

  @visibleForTesting
  Future<void> flushPendingWrites() async {
    final entries = _entries;
    _persistTimer?.cancel();
    _persistTimer = null;
    if (entries == null) return;
    await _persist(entries);
  }
}

class _PersistedExcerpt {
  const _PersistedExcerpt(this.excerpt, this.cachedAtMillis);

  final String excerpt;
  final int cachedAtMillis;
}

String? resolveBestTopicExcerptHtml(Topic topic, {String? cachedHtml}) {
  final resolved = cachedHtml?.trim();
  if (resolved != null && resolved.isNotEmpty) {
    return resolved;
  }

  final excerpt = topic.excerpt?.trim();
  if (excerpt != null && excerpt.isNotEmpty) {
    return excerpt;
  }

  return null;
}

class _CachedExcerpt {
  const _CachedExcerpt(this.excerpt, this.createdAt);

  final String excerpt;
  final DateTime createdAt;
}

class _CachedPreviewDetail {
  const _CachedPreviewDetail(this.detail, this.createdAt);

  final TopicDetail detail;
  final DateTime createdAt;
}

class _QueuedExcerpt {
  const _QueuedExcerpt(this.topicId, this.completer);

  final int topicId;
  final Completer<String?> completer;
}
