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
  'timeout does not send and late success cannot revive the request': () =>
      _withControlledTime((time) async {
        final round = Completer<bool?>();
        var active = true;
        final request = CfReadRequestGate(stopwatch: time.stopwatch).wait(
          method: 'GET',
          isSilent: false,
          skipCfBlock: false,
          isVerifying: () => active,
          waitForVerification: () => round.future,
          timeout: const Duration(milliseconds: 5),
        );
        _check(
          time.timers.single.duration == const Duration(milliseconds: 5),
          'the timeout is armed for the remaining budget',
        );
        time.stopwatch.advance(const Duration(milliseconds: 5));
        time.timers.single.fire();
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
      }),
  'timer expiry is terminal even before the stopwatch reaches its deadline':
      () => _withControlledTime((time) async {
        final round = Completer<bool?>();
        var active = true;
        var waits = 0;
        final gate = CfReadRequestGate(stopwatch: time.stopwatch);
        Future<CfReadGateResult> wait({bool bypass = false}) => gate.wait(
          method: 'GET',
          isSilent: false,
          skipCfBlock: bypass,
          isVerifying: () => active,
          waitForVerification: () {
            waits++;
            if (waits > 1) return Future<bool?>.value(false);
            return round.future;
          },
          timeout: const Duration(milliseconds: 10),
        );
        final request = wait();
        // Dart timers can round a fractional-millisecond remainder down. Fire
        // before the monotonic deadline to reproduce that ordering exactly.
        time.stopwatch.advance(const Duration(microseconds: 9500));
        time.timers.single.fire();
        _check(
          await request == CfReadGateResult.blocked,
          'the timeout callback must finish the wait',
        );
        _check(
          await wait() == CfReadGateResult.blocked,
          'an expired request cannot join a new round',
        );
        _check(
          waits == 1,
          'expiry must be terminal despite a fractional remainder',
        );
        active = false;
        round.complete(true);
        _check(
          await wait() == CfReadGateResult.blocked,
          'an expired request cannot revive when verification becomes idle',
        );
        _check(time.timers.length == 1, 'reuse must not arm another timeout');
        _check(
          await wait(bypass: true) == CfReadGateResult.notNeeded,
          'the explicit internal bypass retains its existing semantics',
        );
      }),
  'adjacent rounds share the original deadline and cannot send early': () =>
      _withControlledTime((time) async {
        var active = true;
        var waits = 0;
        final firstRound = Completer<bool?>();
        final nextRound = Completer<bool?>();
        final gate = CfReadRequestGate(stopwatch: time.stopwatch);
        final request = gate.wait(
          method: 'GET',
          isSilent: false,
          skipCfBlock: false,
          isVerifying: () => active,
          waitForVerification: () =>
              ++waits == 1 ? firstRound.future : nextRound.future,
          timeout: const Duration(milliseconds: 20),
        );
        _check(
          time.timers.single.duration == const Duration(milliseconds: 20),
          'the first round gets the original budget',
        );
        time.stopwatch.advance(const Duration(milliseconds: 7));
        firstRound.complete(true);
        await _flushUntil(
          () => time.timers.length == 2,
          'the second active round must be joined',
        );
        _check(
          !time.timers.first.isActive,
          'the first round cancels its own timeout',
        );
        _check(
          time.timers.last.duration == const Duration(milliseconds: 13),
          'the second round gets only the remaining budget',
        );
        time.stopwatch.advance(const Duration(milliseconds: 13));
        time.timers.last.fire();
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
                timeout: const Duration(milliseconds: 20),
              ) ==
              CfReadGateResult.blocked,
          'later queue admission cannot reset the budget',
        );
        _check(!restarted, 'expired deadline must not join another round');
      }),
  'time back in the scheduler queue still consumes the original deadline': () =>
      _withControlledTime((time) async {
        var active = true;
        var waits = 0;
        final firstRound = Completer<bool?>();
        final gate = CfReadRequestGate(stopwatch: time.stopwatch);
        Future<CfReadGateResult> wait() => gate.wait(
          method: 'GET',
          isSilent: false,
          skipCfBlock: false,
          isVerifying: () => active,
          waitForVerification: () {
            waits++;
            return firstRound.future;
          },
          timeout: const Duration(seconds: 20),
        );
        final request = wait();
        time.stopwatch.advance(const Duration(seconds: 5));
        active = false;
        firstRound.complete(true);
        _check(
          await request == CfReadGateResult.resumed,
          'the first successful round releases normal scheduler admission',
        );
        time.stopwatch.advance(const Duration(seconds: 15));
        active = true;
        _check(
          await wait() == CfReadGateResult.blocked,
          'queue time must not reset the deadline at the next admission',
        );
        _check(waits == 1, 'an expired budget must not join the later round');
        _check(time.timers.length == 1, 'no new timeout is armed after expiry');
        active = false;
        _check(
          await wait() == CfReadGateResult.blocked,
          'monotonic deadline expiry is also terminal once observed',
        );
      }),
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

Future<void> _flushUntil(bool Function() condition, String reason) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.value();
  }
  _check(condition(), reason);
}

Future<void> _withControlledTime(
  Future<void> Function(_ControlledTime time) body,
) async {
  final time = _ControlledTime();
  try {
    await runZoned(
      () => body(time),
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          final timer = _ControlledTimer(duration, callback);
          time.timers.add(timer);
          return timer;
        },
      ),
    );
  } finally {
    for (final timer in time.timers) {
      timer.cancel();
    }
  }
}

class _ControlledTime {
  final stopwatch = _ControlledStopwatch();
  final timers = <_ControlledTimer>[];
}

class _ControlledStopwatch implements Stopwatch {
  Duration _elapsed = Duration.zero;
  bool _running = false;

  void advance(Duration duration) {
    _check(
      _running,
      'the monotonic budget must be running while time advances',
    );
    _elapsed += duration;
  }

  @override
  Duration get elapsed => _elapsed;
  @override
  int get elapsedMicroseconds => _elapsed.inMicroseconds;
  @override
  int get elapsedMilliseconds => _elapsed.inMilliseconds;
  @override
  int get elapsedTicks => _elapsed.inMicroseconds;
  @override
  int get frequency => Duration.microsecondsPerSecond;
  @override
  bool get isRunning => _running;
  @override
  void start() => _running = true;
  @override
  void stop() => _running = false;
  @override
  void reset() => _elapsed = Duration.zero;
}

class _ControlledTimer implements Timer {
  _ControlledTimer(this.duration, this.callback);

  final Duration duration;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    callback();
  }

  @override
  void cancel() => _active = false;
  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
}
