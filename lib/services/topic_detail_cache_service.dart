import 'dart:collection';

import '../models/topic.dart';

/// 话题详情快照缓存。
///
/// 这里只保存运行期内存快照，避免为完整 `TopicDetail` 引入高风险序列化逻辑。
/// 24 小时是硬过期时间；软过期后调用方可以先渲染快照，再后台刷新。
class TopicDetailCacheService {
  TopicDetailCacheService({
    int maxEntries = 20,
    Duration hardTtl = defaultHardTtl,
    Duration softTtl = defaultSoftTtl,
    DateTime Function()? now,
  }) : _maxEntries = maxEntries < 1 ? 1 : maxEntries,
       _hardTtl = hardTtl,
       _softTtl = softTtl,
       _now = now ?? DateTime.now;

  static const defaultHardTtl = Duration(days: 1);
  static const defaultSoftTtl = Duration(minutes: 5);

  final int _maxEntries;
  final Duration _hardTtl;
  final Duration _softTtl;
  final DateTime Function() _now;
  final _entries = LinkedHashMap<String, TopicDetailCacheEntry>();

  TopicDetailCacheEntry? read(
    int topicId, {
    String? username,
    int? targetPostNumber,
  }) {
    _pruneExpired();

    final key = _key(topicId, username);
    final entry = _entries.remove(key);
    if (entry == null) return null;

    if (_isHardExpired(entry)) {
      return null;
    }

    final promoted = entry.copyWith(lastAccessedAt: _now());
    _entries[key] = promoted;

    if (!promoted.containsPostNumber(targetPostNumber)) {
      return null;
    }

    return promoted;
  }

  void write(TopicDetail detail, {String? username}) {
    if (detail.postStream.posts.isEmpty) return;

    final key = _key(detail.id, username);
    final now = _now();
    _entries.remove(key);
    _entries[key] = TopicDetailCacheEntry(
      topicId: detail.id,
      username: username,
      detail: detail,
      loadedAt: now,
      lastAccessedAt: now,
    );

    _pruneExpired();
    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void invalidate(int topicId, {String? username}) {
    _entries.remove(_key(topicId, username));
  }

  void clear() {
    _entries.clear();
  }

  bool shouldRevalidate(
    TopicDetailCacheEntry entry, {
    int? targetPostNumber,
  }) {
    if (targetPostNumber != null) return true;
    return _now().difference(entry.loadedAt) >= _softTtl;
  }

  String _key(int topicId, String? username) {
    return '${username ?? ''}:$topicId';
  }

  bool _isHardExpired(TopicDetailCacheEntry entry) {
    return _now().difference(entry.loadedAt) >= _hardTtl;
  }

  void _pruneExpired() {
    for (final entry in _entries.entries.toList()) {
      if (_isHardExpired(entry.value)) {
        _entries.remove(entry.key);
      }
    }
  }
}

class TopicDetailCacheEntry {
  const TopicDetailCacheEntry({
    required this.topicId,
    required this.username,
    required this.detail,
    required this.loadedAt,
    required this.lastAccessedAt,
  });

  final int topicId;
  final String? username;
  final TopicDetail detail;
  final DateTime loadedAt;
  final DateTime lastAccessedAt;

  bool containsPostNumber(int? postNumber) {
    if (postNumber == null) return true;
    return detail.postStream.posts.any((post) => post.postNumber == postNumber);
  }

  TopicDetailCacheEntry copyWith({
    DateTime? loadedAt,
    DateTime? lastAccessedAt,
  }) {
    return TopicDetailCacheEntry(
      topicId: topicId,
      username: username,
      detail: detail,
      loadedAt: loadedAt ?? this.loadedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    );
  }
}
