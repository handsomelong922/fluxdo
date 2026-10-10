import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/ai_topic_summary_service.dart';

void main() {
  SummaryPost post(int id, [String? text]) => SummaryPost(id, id, 'user$id', text ?? '楼层内容 $id');

  test('从完整目录补齐当前窗口外的主帖及回复，每批最多20条', () async {
    final batches = <List<int>>[];
    final inputs = <String>[];
    final service = AiTopicSummaryService(
      loadTopic: () async => SummarySnapshot('标题', List.generate(61, (i) => i + 1), [post(31)]),
      loadPosts: (ids) async { batches.add(ids); return ids.reversed.map(post).toList(); },
      generate: (_, content, _) async { inputs.add(content); return '总结'; },
    );
    final result = await service.summarize(prompt: '自定义要求', cancellation: TopicSummaryCancellation(), onProgress: (_) {});
    expect(result.readCount, 61);
    expect(result.missingIds, isEmpty);
    expect(batches.every((b) => b.length <= 20), isTrue);
    expect(inputs.single, contains('【#1 @user1】'));
    expect(inputs.single, contains('【#61 @user61】'));
    expect(inputs.single.indexOf('【#1 '), lessThan(inputs.single.indexOf('【#31 ')));
  });

  test('长帖无截断分段且层级合并收敛', () async {
    final inputs = <String>[];
    final source = List.filled(200, '原文🧪').join();
    final service = AiTopicSummaryService(chunkChars: 80, maxChunks: 32,
      loadTopic: () async => SummarySnapshot('标题', [1], [post(1, source)]),
      loadPosts: (_) async => [],
      generate: (_, content, _) async { inputs.add(content); return '段落总结'; },
    );
    final result = await service.summarize(prompt: '要求', cancellation: TopicSummaryCancellation(), onProgress: (_) {});
    final chunks = AiTopicSummaryService.buildPostChunks([post(1, source)], 80);
    expect(inputs.take(chunks.length).join().replaceAll(RegExp(r'【#1 @user1(?:，续)?】\n'), '').trim(), source);
    expect(inputs.take(chunks.length).every((part) => part.contains('@user1')), isTrue);
    expect(inputs.length, chunks.length * 2 - 1);
    expect(result.text, '段落总结');
  });

  test('读取失败不提交局部内容给 AI，重试重新读取', () async {
    var fail = true;
    var calls = 0;
    final service = AiTopicSummaryService(
      loadTopic: () async => SummarySnapshot('标题', [1, 2], [post(1)]),
      loadPosts: (_) async { if (fail) throw StateError('读取失败'); return [post(2)]; },
      generate: (_, _, _) async { calls++; return '总结'; },
    );
    Future<TopicSummaryResult> run() => service.summarize(prompt: '要求', cancellation: TopicSummaryCancellation(), onProgress: (_) {});
    await expectLater(run(), throwsStateError);
    expect(calls, 0);
    fail = false;
    expect((await run()).readCount, 2);
  });

  test('权限不可读楼层明确记录，不谎称全量', () async {
    final service = AiTopicSummaryService(
      loadTopic: () async => SummarySnapshot('标题', [1, 2, 3], [post(1), post(3, '')]),
      loadPosts: (_) async => [], generate: (_, _, _) async => '总结',
    );
    final result = await service.summarize(prompt: '要求', cancellation: TopicSummaryCancellation(), onProgress: (_) {});
    expect(result.readCount, 1);
    expect(result.missingIds, [2, 3]);
  });

  test('读取中取消立即返回，完成中的读取不会触发 AI', () async {
    final fetched = Completer<List<SummaryPost>>();
    final started = Completer<void>();
    var calls = 0;
    final cancellation = TopicSummaryCancellation();
    final service = AiTopicSummaryService(
      loadTopic: () async => SummarySnapshot('标题', [1, 2], [post(1)]),
      loadPosts: (_) { started.complete(); return fetched.future; },
      generate: (_, _, _) async { calls++; return '总结'; },
    );
    final future = service.summarize(prompt: '要求', cancellation: cancellation, onProgress: (_) {});
    final assertion = expectLater(future, throwsA(isA<TopicSummaryException>()));
    await started.future;
    cancellation.cancel();
    await assertion;
    fetched.complete([post(2)]);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0);
  });

  test('AI 生成中取消不再发起后续段落', () async {
    final started = Completer<void>();
    final pending = Completer<String>();
    var calls = 0;
    final token = TopicSummaryCancellation();
    final service = AiTopicSummaryService(chunkChars: 40,
      loadTopic: () async => SummarySnapshot('标题', [1], [post(1, '内容' * 200)]),
      loadPosts: (_) async => [],
      generate: (_, _, _) { calls++; started.complete(); return pending.future; },
    );
    final future = service.summarize(prompt: '要求', cancellation: token, onProgress: (_) {});
    final assertion = expectLater(future, throwsA(isA<TopicSummaryException>()));
    await started.future; token.cancel(); await assertion;
    pending.complete('取消后到达');
    expect(calls, 1);
  });

  test('超限与空 AI 结果均报错', () async {
    var calls = 0;
    final limited = AiTopicSummaryService(maxSourceChars: 10,
      loadTopic: () async => SummarySnapshot('标题', [1], [post(1, '超长内容' * 20)]),
      loadPosts: (_) async => [], generate: (_, _, _) async { calls++; return ''; },
    );
    await expectLater(limited.summarize(prompt: '要求', cancellation: TopicSummaryCancellation(), onProgress: (_) {}), throwsA(isA<TopicSummaryException>()));
    expect(calls, 0);
    final empty = AiTopicSummaryService(
      loadTopic: () async => SummarySnapshot('标题', [1], [post(1)]),
      loadPosts: (_) async => [], generate: (_, _, _) async => '',
    );
    await expectLater(empty.summarize(prompt: '要求', cancellation: TopicSummaryCancellation(), onProgress: (_) {}), throwsA(isA<TopicSummaryException>()));
  });
  test('读取准备后拒绝确认不发送，确认信息包含实际费用规模', () async {
    var calls = 0;
    final service = AiTopicSummaryService(chunkChars: 40,
      loadTopic: () async => SummarySnapshot('标题', [1, 2], [post(1, '内容' * 40)]),
      loadPosts: (_) async => [], generate: (_, _, _) async { calls++; return '总结'; },
    );
    await expectLater(service.summarize(prompt: '要求', cancellation: TopicSummaryCancellation(), onProgress: (_) {},
      onPrepared: (posts, total, chars, requests) async {
        expect(posts, 1); expect(total, 2); expect(chars, greaterThan(80));
        expect(requests, 5); return false;
      }), throwsA(isA<TopicSummaryException>()));
    expect(calls, 0);
  });

}
