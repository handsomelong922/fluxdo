/// 单个详情实例的刷新合并；任一内容更新都优先于仅动作更新。
class TopicPostRefreshQueue {
  final _pending = <int, bool>{};
  final _retry = <int, bool>{};

  bool begin(int postId, {required bool preserveCooked}) {
    if (_pending.containsKey(postId)) {
      _retry[postId] = (_retry[postId] ?? _pending[postId]!) && preserveCooked;
      return false;
    }
    _pending[postId] = preserveCooked;
    return true;
  }

  /// null 表示没有尾部刷新；false 仍然是一条必须执行的内容刷新。
  bool? complete(int postId) {
    _pending.remove(postId);
    return _retry.remove(postId);
  }
}
