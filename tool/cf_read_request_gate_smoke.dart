import 'dart:async';

import '../lib/services/network/cf_read_request_gate.dart';

final cfReadRequestGateSmokeTests = <String, Future<void> Function()>{
  'foreground GET waits for readiness and resumes once': () async {
    final round = Completer<bool?>();
    var active = true;
    var completed = false;
    final gate = CfReadRequestGate();
    final request = gate
        .wait(
          method: 'GET',
          isSilent: false,
          skipCfBlock: false,
          isVerifying: () => active,
          waitForVerification: () => round.future,
        )
        .then((value) {
          completed = true;
          return value;
        });
    await Future<void>.delayed(Duration.zero);
    _check(!completed, 'GET must remain pending while verification is active');
    active = false;
    round.complete(true);
    _check(
      await request == CfReadGateResult.resumed,
      'resume the existing read',
    );
    active = true;
    _check(
      await gate.wait(
            method: 'GET',
            isSilent: false,
            skipCfBlock: false,
            isVerifying: () => active,
            waitForVerification: () async {
              active = false;
              return true;
            },
          ) ==
          CfReadGateResult.resumed,
      'a later already-active round can finish within the same deadline',
    );
  },
  'HEAD and concurrent reads share the existing round': () async {
    var active = true;
    final round = Completer<bool?>();
    final requests = [
      for (final method in ['GET', 'HEAD', 'get'])
        CfReadRequestGate().wait(
          method: method,
          isSilent: false,
          skipCfBlock: false,
          isVerifying: () => active,
          waitForVerification: () => round.future,
        ),
    ];
    active = false;
    round.complete(true);
    _check(
      (await Future.wait(requests)).every((v) => v == CfReadGateResult.resumed),
      'each pending read resumes exactly once',
    );
  },
  'mutations and silent traffic stay blocked without joining verification':
      () async {
        for (final (method, silent) in [
          ('POST', false),
          ('PUT', false),
          ('PATCH', false),
          ('DELETE', false),
          ('OPTIONS', false),
          ('GET', true),
        ]) {
          _check(
            await CfReadRequestGate().wait(
                  method: method,
                  isSilent: silent,
                  skipCfBlock: false,
                  isVerifying: () => true,
                  waitForVerification: () => throw StateError('must not join'),
                ) ==
                CfReadGateResult.blocked,
            '$method silent=$silent must remain blocked',
          );
        }
      },
  'idle and internal bypass requests do not wait': () async {
    for (final (active, bypass) in [(false, false), (true, true)]) {
      _check(
        await CfReadRequestGate().wait(
              method: 'POST',
              isSilent: true,
              skipCfBlock: bypass,
              isVerifying: () => active,
              waitForVerification: () => throw StateError('must not join'),
            ) ==
            CfReadGateResult.notNeeded,
        'idle/bypass keeps existing behavior',
      );
    }
  },
  'failed or missing round outcome does not send a read': () async {
    for (final outcome in [false, null]) {
      _check(
        await CfReadRequestGate().wait(
              method: 'GET',
              isSilent: false,
              skipCfBlock: false,
              isVerifying: () => true,
              waitForVerification: () async => outcome,
            ) ==
            CfReadGateResult.blocked,
        'only true can release a deferred read',
      );
    }
  },
  'cancellation wins without cancelling the shared round': () async {
    final round = Completer<bool?>();
    final cancel = Completer<void>();
    var active = true;
    final request = CfReadRequestGate().wait(
      method: 'GET',
      isSilent: false,
      skipCfBlock: false,
      isVerifying: () => active,
      waitForVerification: () => round.future,
      whenCancelled: cancel.future,
    );
    cancel.complete();
    _check(
      await request == CfReadGateResult.cancelled,
      'cancel must finish promptly',
    );
    _check(
      !round.isCompleted,
      'cancellation must not end another request’s round',
    );
    active = false;
    round.complete(true);
    await Future<void>.delayed(Duration.zero);
    _check(
      await request == CfReadGateResult.cancelled,
      'late success cannot resend',
    );
  },
  'timeout does not send and late success cannot revive the request': () async {
    final round = Completer<bool?>();
    var active = true;
    final request = CfReadRequestGate().wait(
      method: 'GET',
      isSilent: false,
      skipCfBlock: false,
      isVerifying: () => active,
      waitForVerification: () => round.future,
      timeout: const Duration(milliseconds: 5),
    );
    _check(
      await request == CfReadGateResult.blocked,
      'bounded wait must terminate',
    );
    active = false;
    round.complete(true);
    _check(
      await request == CfReadGateResult.blocked,
      'late success cannot resend',
    );
  },
  'adjacent rounds share the original deadline and cannot send early':
      () async {
        var active = true;
        var waits = 0;
        final nextRound = Completer<bool?>();
        final gate = CfReadRequestGate();
        final request = gate.wait(
          method: 'GET',
          isSilent: false,
          skipCfBlock: false,
          isVerifying: () => active,
          waitForVerification: () async {
            if (++waits == 1) return true;
            return nextRound.future;
          },
          timeout: const Duration(milliseconds: 10),
        );
        _check(
          await request == CfReadGateResult.blocked,
          'adjacent round is still bounded',
        );
        _check(
          waits == 2,
          'join the second active round instead of sending early',
        );
        active = false;
        nextRound.complete(true);
        active = true;
        var restarted = false;
        _check(
          await gate.wait(
                method: 'HEAD',
                isSilent: false,
                skipCfBlock: false,
                isVerifying: () => active,
                waitForVerification: () {
                  restarted = true;
                  throw StateError('deadline cannot restart');
                },
                timeout: const Duration(milliseconds: 10),
              ) ==
              CfReadGateResult.blocked,
          'later queue admission cannot reset the budget',
        );
        _check(!restarted, 'expired deadline must not join another round');
      },
  'an adjacent successful round releases the read only after both finish':
      () async {
        var active = true;
        var waits = 0;
        _check(
          await CfReadRequestGate().wait(
                method: 'GET',
                isSilent: false,
                skipCfBlock: false,
                isVerifying: () => active,
                waitForVerification: () async {
                  if (++waits == 2) active = false;
                  return true;
                },
              ) ==
              CfReadGateResult.resumed,
          'both captured rounds must finish',
        );
        _check(waits == 2, 'exactly two existing rounds joined');
      },
  'readiness exceptions fail closed': () async {
    _check(
      await CfReadRequestGate().wait(
            method: 'GET',
            isSilent: false,
            skipCfBlock: false,
            isVerifying: () => true,
            waitForVerification: () async => throw StateError('sync failed'),
          ) ==
          CfReadGateResult.blocked,
      'failed readiness must not send',
    );
  },
};

Future<void> main() async {
  for (final test in cfReadRequestGateSmokeTests.entries) {
    await test.value();
    print('PASS: ${test.key}');
  }
  print('${cfReadRequestGateSmokeTests.length} CF read gate checks passed');
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}
