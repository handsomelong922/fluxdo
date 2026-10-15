import '../lib/utils/topic_post_refresh_queue.dart';

void check(bool condition) {
  if (!condition) throw StateError('单帖刷新合并回归失败');
}

void main() {
  for (final first in [true, false]) {
    for (final second in [true, false]) {
      for (final third in [true, false]) {
        final queue = TopicPostRefreshQueue();
        check(queue.begin(1, preserveCooked: first));
        check(!queue.begin(1, preserveCooked: second));
        check(!queue.begin(1, preserveCooked: third));
        check(queue.complete(1) == (first && second && third));
        check(queue.begin(1, preserveCooked: true));
        check(queue.complete(1) == null);
      }
    }
  }
  final first = TopicPostRefreshQueue();
  final second = TopicPostRefreshQueue();
  check(first.begin(1, preserveCooked: true));
  check(second.begin(1, preserveCooked: false));
  check(first.begin(2, preserveCooked: false));
  print('PASS: acted/revised 全组合、无尾部请求、不同帖子/页面互不阻塞');
}
