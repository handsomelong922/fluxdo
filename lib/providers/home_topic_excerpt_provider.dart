import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'discourse_providers.dart';
import 'preferences_provider.dart';
import 'theme_provider.dart';

typedef TopicExcerptFetcher = Future<String?> Function(int topicId);

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
    fetchExcerpt: (topicId) => ref
        .read(discourseServiceProvider)
        .getTopicFirstPostCooked(topicId, background: true),
  );
  ref.onDispose(loader.dispose);
  return loader;
});

final homeTopicExcerptProvider = FutureProvider.autoDispose
    .family<String?, int>((ref, topicId) async {
      final keepAlive = ref.keepAlive();
      final excerpt = await ref
          .watch(homeTopicExcerptLoaderProvider)
          .load(topicId);
      if (excerpt == null || excerpt.trim().isEmpty) {
        keepAlive.close();
      }
      return excerpt;
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
    required TopicExcerptFetcher fetchExcerpt,
    int maxCacheEntries = 160,
    Duration cacheTtl = defaultCacheTtl,
    int maxConcurrentRequests = 3,
    Duration minRequestInterval = const Duration(milliseconds: 120),
    Duration failureCooldown = const Duration(seconds: 45),
    Duration requestTimeout = const Duration(seconds: 8),
    HomeTopicExcerptPersistentCache? persistentCache,
  }) : _fetchExcerpt = fetchExcerpt,
       _maxCacheEntries = maxCacheEntries,
       _cacheTtl = cacheTtl,
       _maxConcurrentRequests = maxConcurrentRequests.clamp(1, 8).toInt(),
       _minRequestInterval = minRequestInterval,
       _failureCooldown = failureCooldown,
       _requestTimeout = requestTimeout,
       _persistentCache = persistentCache;

  final TopicExcerptFetcher _fetchExcerpt;
  final int _maxCacheEntries;
  final Duration _cacheTtl;
  final int _maxConcurrentRequests;
  final Duration _minRequestInterval;
  final Duration _failureCooldown;
  final Duration _requestTimeout;
  final HomeTopicExcerptPersistentCache? _persistentCache;

  final _cache = <int, _CachedExcerpt>{};
  final _inFlight = <int, Future<String?>>{};
  final _failureUntil = <int, DateTime>{};
  final _pendingQueue = Queue<_QueuedExcerpt>();

  Future<void> _startSlotTail = Future<void>.value();
  DateTime? _lastRequestStartedAt;
  int _activeRequests = 0;
  bool _disposed = false;

  String? peekCached(int topicId) {
    if (_disposed) return null;
    return _readCache(topicId);
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
    _inFlight.clear();
    _failureUntil.clear();
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
      final excerpt = await _fetchExcerpt(topicId).timeout(_requestTimeout);
      if (excerpt != null && excerpt.trim().isNotEmpty) {
        _writeCache(topicId, excerpt);
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

  void _writeCache(int topicId, String excerpt) {
    _writeMemoryCache(topicId, excerpt);
    unawaited(_persistentCache?.write(topicId, excerpt, _cacheTtl));
  }

  void _writeMemoryCache(int topicId, String excerpt) {
    _cache.remove(topicId);
    _cache[topicId] = _CachedExcerpt(excerpt, DateTime.now());
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
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
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const storageKey = 'home_topic_excerpt_cache_v1';

  final SharedPreferences _prefs;
  final int maxEntries;
  final DateTime Function() _now;

  Map<int, _PersistedExcerpt>? _entries;

  String? read(int topicId, Duration ttl) {
    final entries = _loadEntries();
    final entry = entries.remove(topicId);
    if (entry == null) return null;

    if (_isExpired(entry.cachedAtMillis, ttl)) {
      unawaited(_persist(entries));
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
    await _persist(entries);
  }

  Future<void> pruneExpired(Duration ttl) async {
    final entries = _loadEntries();
    final changed = _pruneExpiredEntries(entries, ttl);
    if (changed) {
      await _persist(entries);
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
}

class _PersistedExcerpt {
  const _PersistedExcerpt(this.excerpt, this.cachedAtMillis);

  final String excerpt;
  final int cachedAtMillis;
}

class _CachedExcerpt {
  const _CachedExcerpt(this.excerpt, this.createdAt);

  final String excerpt;
  final DateTime createdAt;
}

class _QueuedExcerpt {
  const _QueuedExcerpt(this.topicId, this.completer);

  final int topicId;
  final Completer<String?> completer;
}
