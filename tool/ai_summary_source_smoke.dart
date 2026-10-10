import 'dart:async';

import '../lib/services/ai_topic_summary_service.dart';

Future<void> main() async {
  final ids = List.generate(65, (i) => i + 1);
  final seen = <int>[];
  var calls = 0;
  final service = AiTopicSummaryService(
    chunkChars: 180,
    loadTopic: () async =>
        SummarySnapshot('标题', ids, [const SummaryPost(32, 32, 'u', '楼层32')]),
    loadPosts: (batch) async {
      assert(batch.length <= 20);
      seen.addAll(batch);
      return batch.map((id) => SummaryPost(id, id, 'u', '楼层$id')).toList();
    },
    generate: (_, _, _) async {
      calls++;
      return '摘要';
    },
  );
  var expected = 0;
  final result = await service.summarize(
    prompt: '总结',
    cancellation: TopicSummaryCancellation(),
    onProgress: (_) {},
    onPrepared: (posts, total, chars, requests) async {
      assert(posts == 65 && total == 65);
      expected = requests;
      return true;
    },
  );
  assert(result.readCount == 65 && result.missingIds.isEmpty);
  assert(seen.length == 64 && calls == expected && calls > 1);
  final cancellation = TopicSummaryCancellation();
  final pending = Completer<SummarySnapshot>();
  final cancelled = AiTopicSummaryService(
    loadTopic: () => pending.future,
    loadPosts: (_) async => [],
    generate: (_, _, _) async => throw StateError('不得调用AI'),
  );
  final future = cancelled.summarize(
    prompt: '总结',
    cancellation: cancellation,
    onProgress: (_) {},
  );
  cancellation.cancel();
  try {
    await future;
    throw StateError('没有取消');
  } on TopicSummaryException catch (_) {}
  pending.complete(const SummarySnapshot('标题', [], []));
  final emojis = List.filled(100, '🧪').join();
  assert(AiTopicSummaryService.splitText(emojis, 3).join() == emojis);
  print('PASS: 全量65楼、20条批量、分段合并调用数、取消、Unicode无损');
}
