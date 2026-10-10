import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/ai_topic_summary_service.dart';
import 'package:fluxdo/services/ai_topic_summary_task.dart';

AiTopicSummaryService service(Future<String> Function() generate) => AiTopicSummaryService(
  loadTopic: () async => const SummarySnapshot('Topic', [1], [SummaryPost(1, 1, 'author', 'body')]),
  loadPosts: (_) async => [], generate: (_, _, _) => generate());

void main() {
  test('后台任务没有监听者仍完成，重复入口去重，重启恢复快照', () async {
    final cache = <String, String>{};
    AiTopicSummaryTasks create() => AiTopicSummaryTasks(readCache: (k) => cache[k],
      writeCache: (k, v) async { cache[k] = v; return true; });
    final tasks = create();
    final pending = Completer<String>();
    var calls = 0;
    final future = tasks.start('account-topic-model-prompt', prompt: 'summarize',
      createService: () async => service(() { calls++; return pending.future; }));
    await Future<void>.delayed(Duration.zero);
    await tasks.start('account-topic-model-prompt', prompt: 'summarize',
      createService: () async => throw StateError('must deduplicate'));
    expect(calls, 1);
    expect(tasks.state('account-topic-model-prompt').busy, isTrue);
    pending.complete('summary');
    await future;
    expect(tasks.state('account-topic-model-prompt').result!.text, 'summary');
    tasks.dispose();
    final restored = create();
    expect(restored.state('account-topic-model-prompt').result!.text, 'summary');
    await restored.start('account-topic-model-prompt', prompt: 'summarize',
      createService: () async => throw StateError('cache should avoid request'));
    expect(restored.state('account-topic-model-prompt').savedAt, isNotNull);
    expect(restored.state('another-account').result, isNull);
    restored.dispose();
  });

  test('取消后可立即重试，迟到结果不能覆盖新任务', () async {
    final cache = <String, String>{};
    final tasks = AiTopicSummaryTasks(readCache: (k) => cache[k],
      writeCache: (k, v) async { cache[k] = v; return true; });
    final pending = Completer<String>();
    final old = tasks.start('key', prompt: 'p', createService: () async => service(() => pending.future));
    await Future<void>.delayed(Duration.zero);
    tasks.cancel('key');
    expect(tasks.state('key').error, '已取消总结');
    await tasks.start('key', prompt: 'p', retry: true, createService: () async => service(() async => 'new'));
    pending.complete('old');
    await old;
    expect(tasks.state('key').result!.text, 'new');
    expect(cache['key'], contains('new'));
    tasks.dispose();
  });

  test('账号退出销毁任务，API key 读取迟到不能启动或保存结果', () async {
    final credentials = Completer<AiTopicSummaryService>();
    var calls = 0;
    var saves = 0;
    final tasks = AiTopicSummaryTasks(readCache: (_) => null,
      writeCache: (_, _) async { saves++; return true; });
    final future = tasks.start('account-a', prompt: 'p', createService: () => credentials.future);
    tasks.dispose();
    credentials.complete(service(() async { calls++; return 'secret'; }));
    await future;
    expect(calls, 0);
    expect(saves, 0);
    expect(tasks.state('account-a').result, isNull);
  });

  test('生成中退出账号不会保存迟到结果', () async {
    final pending = Completer<String>();
    var saves = 0;
    final tasks = AiTopicSummaryTasks(readCache: (_) => null,
      writeCache: (_, _) async { saves++; return true; });
    final future = tasks.start('account-a', prompt: 'p', createService: () async => service(() => pending.future));
    await Future<void>.delayed(Duration.zero);
    tasks.dispose();
    pending.complete('secret');
    await future;
    expect(saves, 0);
  });

  test('错误可重试且不暴露原始服务异常，刷新失败保留旧总结', () async {
    final tasks = AiTopicSummaryTasks(readCache: (_) => null, writeCache: (_, _) async => true);
    await tasks.start('key', prompt: 'p', createService: () async => throw StateError('secret-key'));
    expect(tasks.state('key').error, isNot(contains('secret-key')));
    await tasks.start('key', prompt: 'p', retry: true, createService: () async => service(() async => 'good'));
    await tasks.start('key', prompt: 'p', retry: true,
      createService: () async => service(() async => throw const TopicSummaryException('重试错误')));
    expect(tasks.state('key').result!.text, 'good');
    expect(tasks.state('key').error, '重试错误');
    expect(tasks.state('key').busy, isFalse);
    tasks.dispose();
  });

  test('损坏缓存回退生成，本地保存失败仍保留已生成结果', () async {
    final tasks = AiTopicSummaryTasks(readCache: (_) => '{bad json',
      writeCache: (_, _) async => throw StateError('disk full'));
    expect(tasks.state('key').result, isNull);
    await tasks.start('key', prompt: 'p', createService: () async => service(() async => 'good'));
    expect(tasks.state('key').result!.text, 'good');
    expect(tasks.state('key').error, contains('本地保存失败'));
    tasks.dispose();
  });

  test('模型或 Prompt 改变使用独立任务，不覆盖其他结果', () async {
    final tasks = AiTopicSummaryTasks(readCache: (_) => null, writeCache: (_, _) async => true);
    for (final key in ['topic-model-a-prompt-a', 'topic-model-b-prompt-a', 'topic-model-b-prompt-b']) {
      await tasks.start(key, prompt: 'p', createService: () async => service(() async => key));
    }
    expect(tasks.state('topic-model-a-prompt-a').result!.text, 'topic-model-a-prompt-a');
    expect(tasks.state('topic-model-b-prompt-b').result!.text, 'topic-model-b-prompt-b');
    tasks.dispose();
  });
}
