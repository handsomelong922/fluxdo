import 'dart:collection';

import '../models/topic.dart';

typedef TopicRelatedTopicsFetcher =
    Future<List<Topic>> Function(int topicId, int postNumber);

/// 网页端“相关帖子”的短期缓存与并发复用。
///
/// 该 loader 不做轮询或重试；失败由调用方静默隔离，后续显式用户动作可再次请求。
class TopicRelatedTopicsLoader {
  TopicRelatedTopicsLoader({
    required TopicRelatedTopicsFetcher fetch,
    Duration cacheTtl = const Duration(minutes: 10),
    int maxEntries = 64,
    DateTime Function()? now,
  }) : _fetch = fetch,
       _cacheTtl = cacheTtl,
       _maxEntries = maxEntries.clamp(1, 256).toInt(),
       _now = now ?? DateTime.now;

  final TopicRelatedTopicsFetcher _fetch;
  final Duration _cacheTtl;
  final int _maxEntries;
  final DateTime Function() _now;
  final LinkedHashMap<_RelatedTopicsKey, _RelatedTopicsCacheEntry> _cache =
      LinkedHashMap<_RelatedTopicsKey, _RelatedTopicsCacheEntry>();
  final Map<_RelatedTopicsKey, Future<List<Topic>>> _inFlight =
      <_RelatedTopicsKey, Future<List<Topic>>>{};

  Future<List<Topic>> load({
    required int topicId,
    required int postNumber,
    String? viewerKey,
  }) {
    final key = _RelatedTopicsKey(
      topicId: topicId,
      postNumber: postNumber,
      viewerKey: viewerKey ?? '',
    );
    final cached = _readCache(key);
    if (cached != null) return Future<List<Topic>>.value(cached);

    final existing = _inFlight[key];
    if (existing != null) return existing;

    late final Future<List<Topic>> request;
    request = _fetch(topicId, postNumber)
        .then((topics) {
          final immutable = List<Topic>.unmodifiable(topics);
          _writeCache(key, immutable);
          return immutable;
        })
        .whenComplete(() {
          if (identical(_inFlight[key], request)) {
            _inFlight.remove(key);
          }
        });
    _inFlight[key] = request;
    return request;
  }

  void clear() {
    _cache.clear();
    _inFlight.clear();
  }

  List<Topic>? _readCache(_RelatedTopicsKey key) {
    final entry = _cache.remove(key);
    if (entry == null) return null;
    if (_now().difference(entry.createdAt) > _cacheTtl) return null;
    _cache[key] = entry;
    return entry.topics;
  }

  void _writeCache(_RelatedTopicsKey key, List<Topic> topics) {
    _cache.remove(key);
    _cache[key] = _RelatedTopicsCacheEntry(topics, _now());
    while (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }
}

class _RelatedTopicsKey {
  const _RelatedTopicsKey({
    required this.topicId,
    required this.postNumber,
    required this.viewerKey,
  });

  final int topicId;
  final int postNumber;
  final String viewerKey;

  @override
  bool operator ==(Object other) {
    return other is _RelatedTopicsKey &&
        other.topicId == topicId &&
        other.postNumber == postNumber &&
        other.viewerKey == viewerKey;
  }

  @override
  int get hashCode => Object.hash(topicId, postNumber, viewerKey);
}

class _RelatedTopicsCacheEntry {
  const _RelatedTopicsCacheEntry(this.topics, this.createdAt);

  final List<Topic> topics;
  final DateTime createdAt;
}
