import '../models/topic.dart';

/// 话题详情快照缓存。
///
/// 这里只保存运行期内存快照，避免为完整 `TopicDetail` 引入高风险序列化逻辑。
/// 24 小时是硬过期时间；软过期后调用方可以先渲染快照，再后台刷新。
class TopicDetailCacheService {
  TopicDetailCacheService({
    int maxEntries = 20,
    int maxCacheablePosts = 160,
    int maxCacheableContentChars = 4 * 1024 * 1024,
    int maxTotalContentChars = 16 * 1024 * 1024,
    Duration hardTtl = defaultHardTtl,
    Duration softTtl = defaultSoftTtl,
    DateTime Function()? now,
  }) : _maxEntries = maxEntries < 1 ? 1 : maxEntries,
       _maxCacheablePosts = maxCacheablePosts < 1 ? 1 : maxCacheablePosts,
       _maxCacheableContentChars = maxCacheableContentChars < 1
           ? 1
           : maxCacheableContentChars,
       _maxTotalContentChars = maxTotalContentChars < 1
           ? 1
           : maxTotalContentChars,
       _hardTtl = hardTtl,
       _softTtl = softTtl,
       _now = now ?? DateTime.now;

  static const defaultHardTtl = Duration(days: 1);
  static const defaultSoftTtl = Duration(minutes: 5);

  final int _maxEntries;
  final int _maxCacheablePosts;
  final int _maxCacheableContentChars;
  final int _maxTotalContentChars;
  final Duration _hardTtl;
  final Duration _softTtl;
  final DateTime Function() _now;
  final _entries = <String, TopicDetailCacheEntry>{};

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

    if (!promoted.containsPostNumber(targetPostNumber) &&
        !promoted.isPreviewSeed) {
      return null;
    }

    return promoted;
  }

  void write(TopicDetail detail, {String? username}) {
    _writeEntry(detail, username: username, isPreviewSeed: false);
  }

  void writePreviewSeed(TopicDetail detail, {String? username}) {
    _writeEntry(detail, username: username, isPreviewSeed: true);
  }

  void _writeEntry(
    TopicDetail detail, {
    String? username,
    required bool isPreviewSeed,
  }) {
    if (detail.postStream.posts.isEmpty) return;

    final key = _key(detail.id, username);
    _entries.remove(key);
    final contentChars = _estimateContentChars(detail);
    if (!isPreviewSeed &&
        (detail.postStream.posts.length > _maxCacheablePosts ||
            contentChars > _maxCacheableContentChars)) {
      _pruneExpired();
      return;
    }

    final now = _now();
    _entries[key] = TopicDetailCacheEntry(
      topicId: detail.id,
      username: username,
      detail: detail,
      loadedAt: now,
      lastAccessedAt: now,
      isPreviewSeed: isPreviewSeed,
      contentChars: contentChars,
    );

    _pruneExpired();
    _pruneToBudget(preserveKey: key);
  }

  void invalidate(int topicId, {String? username}) {
    _entries.remove(_key(topicId, username));
  }

  void clear() {
    _entries.clear();
  }

  bool shouldRevalidate(TopicDetailCacheEntry entry, {int? targetPostNumber}) {
    if (entry.isPreviewSeed) return true;
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

  int _estimateContentChars(TopicDetail detail) {
    var total = 0;
    for (final post in detail.postStream.posts) {
      total += post.cooked.length;
      total += post.signatureCooked?.length ?? 0;
    }
    return total;
  }

  int get _totalContentChars => _entries.values.fold<int>(
    0,
    (total, entry) => total + entry.contentChars,
  );

  void _pruneToBudget({required String preserveKey}) {
    while (_entries.length > _maxEntries ||
        _totalContentChars > _maxTotalContentChars) {
      String? evictionKey;
      for (final key in _entries.keys) {
        if (key != preserveKey) {
          evictionKey = key;
          break;
        }
      }
      if (evictionKey == null) return;
      _entries.remove(evictionKey);
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
    this.isPreviewSeed = false,
    required this.contentChars,
  });

  final int topicId;
  final String? username;
  final TopicDetail detail;
  final DateTime loadedAt;
  final DateTime lastAccessedAt;
  final bool isPreviewSeed;
  final int contentChars;

  bool containsPostNumber(int? postNumber) {
    if (postNumber == null) return true;
    return detail.postStream.posts.any((post) => post.postNumber == postNumber);
  }

  TopicDetailCacheEntry copyWith({
    DateTime? loadedAt,
    DateTime? lastAccessedAt,
    bool? isPreviewSeed,
  }) {
    return TopicDetailCacheEntry(
      topicId: topicId,
      username: username,
      detail: detail,
      loadedAt: loadedAt ?? this.loadedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      isPreviewSeed: isPreviewSeed ?? this.isPreviewSeed,
      contentChars: contentChars,
    );
  }
}
