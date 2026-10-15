import '../lib/utils/topic_new_post_retry.dart';

void main() {
  final retry = TopicNewPostRetry();
  final delays = List.generate(8, (_) => retry.failed()?.inSeconds);
  if (delays.join(',') != '3,6,12,24,48,null,null,null') {
    throw StateError('重试必须有界指数退避: $delays');
  }
  retry.succeeded();
  if (retry.failed()?.inSeconds != 3) throw StateError('成功后未归零');
  final oldGeneration = retry.generation;
  retry.reset();
  if (retry.generation == oldGeneration || retry.failed()?.inSeconds != 3) {
    throw StateError('重载未隔离旧响应和预算');
  }
  print('PASS: 3/6/12/24/48 秒有界退避、恢复预算、重载代次隔离');
}
