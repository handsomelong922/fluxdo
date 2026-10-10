import 'dart:async';

import '../lib/services/ai_topic_summary_task.dart';
import '../lib/services/ai_topic_summary_service.dart';

AiTopicSummaryService service(Future<String> Function() generate) =>
    AiTopicSummaryService(
      loadTopic: () async =>
          const SummarySnapshot('title', [1], [SummaryPost(1, 1, 'a', 'body')]),
      loadPosts: (_) async => [],
      generate: (_, _, _) => generate(),
    );
Future<void> main() async {
  final cache = <String, String>{};
  AiTopicSummaryTasks create() => AiTopicSummaryTasks(
    readCache: (k) => cache[k],
    writeCache: (k, v) async {
      cache[k] = v;
      return true;
    },
  );
  final tasks = create();
  final pending = Completer<String>();
  var calls = 0;
  final run = tasks.start(
    'key',
    prompt: 'p',
    createService: () async => service(() {
      calls++;
      return pending.future;
    }),
  );
  await Future<void>.delayed(Duration.zero);
  await tasks.start(
    'key',
    prompt: 'p',
    createService: () async => throw 'duplicate',
  );
  assert(calls == 1 && tasks.state('key').busy);
  pending.complete('summary');
  await run;
  assert(tasks.state('key').result!.text == 'summary');
  tasks.dispose();
  final restored = create();
  assert(restored.state('key').result!.text == 'summary');
  assert(restored.state('other-account').result == null);
  final late = Completer<String>();
  final run2 = restored.start(
    'cancel',
    prompt: 'p',
    createService: () async => service(() => late.future),
  );
  await Future<void>.delayed(Duration.zero);
  restored.cancel('cancel');
  assert(restored.state('cancel').error == '已取消总结');
  await restored.start(
    'cancel',
    prompt: 'p',
    retry: true,
    createService: () async => service(() async => 'new'),
  );
  late.complete('old');
  await run2;
  assert(restored.state('cancel').result!.text == 'new');
  await restored.start(
    'cancel',
    prompt: 'p',
    retry: true,
    createService: () async => throw 'api-secret',
  );
  assert(restored.state('cancel').result!.text == 'new');
  assert(!restored.state('cancel').error!.contains('api-secret'));
  restored.dispose();
  var saves = 0;
  final key = Completer<AiTopicSummaryService>();
  final dying = AiTopicSummaryTasks(
    readCache: (_) => null,
    writeCache: (_, _) async {
      saves++;
      return true;
    },
  );
  final run3 = dying.start(
    'secret',
    prompt: 'p',
    createService: () => key.future,
  );
  dying.dispose();
  key.complete(
    service(() async {
      calls++;
      return 'secret';
    }),
  );
  await run3;
  assert(saves == 0 && calls == 1);
  final corrupt = AiTopicSummaryTasks(
    readCache: (_) => '{bad',
    writeCache: (_, _) async => throw 'disk',
  );
  assert(corrupt.state('key').result == null);
  await corrupt.start(
    'key',
    prompt: 'p',
    createService: () async => service(() async => 'safe'),
  );
  assert(corrupt.state('key').result!.text == 'safe');
  assert(corrupt.state('key').error!.contains('本地保存失败'));
  corrupt.dispose();
  print(
    'PASS: dedup/background/cache restore/account isolation/cancel-retry/late suppression/error redaction/dispose-before-key/cache corruption/save failure',
  );
}
