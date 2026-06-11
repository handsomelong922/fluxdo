import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'discourse_providers.dart';
import 'preferences_provider.dart';

typedef TopicExcerptFetcher = Future<String?> Function(int topicId);

final homeTopicExcerptLoaderProvider = Provider<HomeTopicExcerptLoader>((ref) {
  final batchSize = ref.watch(
    preferencesProvider.select((p) => p.homeExcerptBatchSize),
  );
  final loader = HomeTopicExcerptLoader(
    maxConcurrentRequests: batchSize,
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

class HomeTopicExcerptLoader {
  HomeTopicExcerptLoader({
    required TopicExcerptFetcher fetchExcerpt,
    int maxCacheEntries = 160,
    Duration cacheTtl = const Duration(minutes: 30),
    int maxConcurrentRequests = 3,
    Duration minRequestInterval = const Duration(milliseconds: 120),
    Duration failureCooldown = const Duration(seconds: 45),
    Duration requestTimeout = const Duration(seconds: 8),
  }) : _fetchExcerpt = fetchExcerpt,
       _maxCacheEntries = maxCacheEntries,
       _cacheTtl = cacheTtl,
       _maxConcurrentRequests = maxConcurrentRequests.clamp(1, 8).toInt(),
       _minRequestInterval = minRequestInterval,
       _failureCooldown = failureCooldown,
       _requestTimeout = requestTimeout;

  final TopicExcerptFetcher _fetchExcerpt;
  final int _maxCacheEntries;
  final Duration _cacheTtl;
  final int _maxConcurrentRequests;
  final Duration _minRequestInterval;
  final Duration _failureCooldown;
  final Duration _requestTimeout;

  final _cache = <int, _CachedExcerpt>{};
  final _inFlight = <int, Future<String?>>{};
  final _failureUntil = <int, DateTime>{};
  final _pendingQueue = Queue<_QueuedExcerpt>();

  Future<void> _startSlotTail = Future<void>.value();
  DateTime? _lastRequestStartedAt;
  int _activeRequests = 0;
  bool _disposed = false;

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
    for (final queued in _pendingQueue) {
      _completeIfNeeded(queued.completer, null);
    }
    _pendingQueue.clear();
    _cache.clear();
    _inFlight.clear();
    _failureUntil.clear();
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
    if (entry == null) return null;

    if (DateTime.now().difference(entry.createdAt) > _cacheTtl) {
      return null;
    }

    _cache[topicId] = entry;
    return entry.excerpt;
  }

  void _writeCache(int topicId, String excerpt) {
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
