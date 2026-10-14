import 'dart:async';

import '../lib/services/cf_verification_readiness.dart';

final cfVerificationReadinessSmokeTests = <String, Future<void> Function()>{
  '验证成功仍需等待 Cookie 快照和原生析构': () async {
    for (final cookieFirst in [true, false]) {
      final cookies = Completer<void>();
      final teardown = Completer<void>();
      var settled = false;
      final ready =
          waitForCfVerificationCleanup(
            verificationPassed: true,
            cookieSync: cookies.future,
            teardown: teardown.future,
          ).then((result) {
            settled = true;
            return result;
          });
      (cookieFirst ? cookies : teardown).complete();
      await Future<void>.delayed(Duration.zero);
      _check(!settled, '只完成其中一项不能放行');
      (cookieFirst ? teardown : cookies).complete();
      _check(await ready, '两项完成后应恢复');
    }
  },
  '快照同步失败不能报告恢复成功': () async {
    final cookies = Completer<void>();
    final ready = waitForCfVerificationCleanup(
      verificationPassed: true,
      cookieSync: cookies.future,
      teardown: Future<void>.value(),
    );
    cookies.completeError(StateError('snapshot failed'));
    _check(!await ready, '同步失败应返回 false');
  },
  '清理超时会释放等待，迟到同步不能更改结果': () async {
    final cookies = Completer<void>();
    final ready = waitForCfVerificationCleanup(
      verificationPassed: true,
      cookieSync: cookies.future,
      teardown: Future<void>.value(),
      timeout: const Duration(milliseconds: 10),
    );
    _check(!await ready, '失去响应的快照必须有界结束');
    cookies.complete();
    _check(!await ready, '迟到完成不能把超时改成成功');
  },
  '取消验证等待析构后返回 false': () async {
    final teardown = Completer<void>();
    var settled = false;
    final ready =
        waitForCfVerificationCleanup(
          verificationPassed: false,
          teardown: teardown.future,
        ).then((result) {
          settled = true;
          return result;
        });
    await Future<void>.delayed(Duration.zero);
    _check(!settled, '取消也不能抢在析构前结束');
    teardown.complete();
    _check(!await ready, '取消必须保持 false');
  },
};

Future<void> main() async {
  for (final entry in cfVerificationReadinessSmokeTests.entries) {
    await entry.value();
    print('通过：${entry.key}');
  }
  print('恢复就绪策略 ${cfVerificationReadinessSmokeTests.length} 项全部通过');
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}
