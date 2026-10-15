import 'dart:io';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final loading = File('lib/providers/topic_detail/_loading_methods.dart').readAsStringSync();
  final provider = File('lib/providers/topic_detail_provider.dart').readAsStringSync();
  final filters = File('lib/providers/topic_detail/_filter_methods.dart').readAsStringSync();
  final updates = File('lib/providers/topic_detail/_post_updates.dart').readAsStringSync();
  final refresh = loading.split('Future<void> refreshWithPostNumber').last
      .split('Future<int> loadPostNumber').first;
  require(refresh.contains('filterTopLevelReplies: _filterTopLevelReplies'),
      '刷新必须传递顶层过滤');
  for (final body in [refresh,
    loading.split('Future<void> reloadWithPostNumber').last,
    filters.split('Future<void> _reloadWithFilter').last,
  ]) {
    require(body.contains('_resetPendingNewPosts();'), '整体重载必须清空待拉状态');
  }
  final pending = loading.split('Future<void> _loadPendingNewPosts').last
      .split('Future<void> reloadWithPostNumber').first;
  require(!pending.contains('await Future.delayed'), '退避不能占用加载锁');
  require(pending.indexOf('_isLoadingNewPosts = false') < pending.indexOf('Timer(retryDelay'),
      '必须先释放加载锁，再安排重试');
  require(pending.contains('generation != _newPostRetry.generation'), '旧响应必须被隔离');
  require(provider.contains('disposeTimer?.cancel();\n      _resetPendingNewPosts();'),
      '卸载时必须取消新帖定时器');
  require(updates.contains('refreshPost(postId, preserveCooked: retryPreserveCooked)'),
      '尾部刷新必须传递合并后的参数');
  print('PASS: 顶层过滤、重载/卸载取消、退避释放锁、旧响应隔离、尾部参数源码契约');
}
