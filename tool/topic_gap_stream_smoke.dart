import '../lib/utils/topic_gap_stream.dart';

void check(bool value) {
  if (!value) throw StateError('gap 目录回归失败');
}

void main() {
  for (final before in [true, false]) {
    final original = [10, 40, 50];
    final merged = mergeTopicGapStream(
      stream: original,
      anchorId: before ? 40 : 10,
      before: before,
      gapIds: [20, 30, 30, 99, 40],
      fetchedIds: [30, 20, 40],
    )!;
    check(merged.join(',') == '10,20,30,40,50');
    check(original.join(',') == '10,40,50');
    check(merged.indexOf(50) == merged.length - 1);
  }
  check(mergeTopicGapStream(stream: [1], anchorId: 2, before: true,
      gapIds: [3], fetchedIds: [3]) == null);
  check(mergeTopicGapStream(stream: [1, 2], anchorId: 2, before: true,
      gapIds: [3], fetchedIds: [])!.join(',') == '1,2');
  print('PASS: gap 前后原位插入、去重、部分响应、边界、过期锚点');
}
