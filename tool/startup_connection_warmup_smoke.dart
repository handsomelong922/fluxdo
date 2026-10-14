import 'dart:async';

import '../lib/services/startup_connection_warmup.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

final startupWarmupSmokeTests = <String, Future<void> Function()>{
  'valid connection probes once and concurrent callers join': () async {
    final warmup = StartupConnectionWarmup();
    var probes = 0;
    final ready = Completer<void>();
    Future<void> run() => warmup.start(
      canRun: () => true,
      prepare: () => ready.future,
      joinVerification: () async => null,
      probe: () async {
        probes++;
      },
    );
    final first = run();
    check(identical(first, run()), 'must join process-wide task');
    ready.complete();
    await first;
    await run();
    check(probes == 1, 'must not probe twice');
  },
  'offline failure is contained without retry': () async {
    var probes = 0;
    await StartupConnectionWarmup().start(
      canRun: () => true,
      prepare: () async {},
      joinVerification: () async => null,
      probe: () async {
        probes++;
        throw StateError('offline');
      },
    );
    check(probes == 1, 'only normal single probe');
  },
  'disabled or background skips preparation and request': () async {
    var calls = 0;
    await StartupConnectionWarmup().start(
      canRun: () => false,
      prepare: () async {
        calls++;
      },
      joinVerification: () async {
        calls++;
        return null;
      },
      probe: () async {
        calls++;
      },
    );
    check(calls == 0, 'disabled task must do nothing');
  },
  'dispose while preparing prevents request': () async {
    final warmup = StartupConnectionWarmup();
    var probes = 0;
    await warmup.start(
      canRun: () => true,
      prepare: () async => warmup.cancel(),
      joinVerification: () async => null,
      probe: () async {
        probes++;
      },
    );
    check(probes == 0, 'cancelled preparation must not probe');
  },
  'lifecycle change while preparing prevents request': () async {
    var mounted = true;
    var probes = 0;
    await StartupConnectionWarmup().start(
      canRun: () => mounted,
      prepare: () async {
        mounted = false;
      },
      joinVerification: () async => null,
      probe: () async {
        probes++;
      },
    );
    check(probes == 0, 'unmounted preparation must not probe');
  },
  'session changes while joining prevent probe': () async {
    var validSession = true;
    var probes = 0;
    await StartupConnectionWarmup().start(
      canRun: () => validSession,
      prepare: () async {},
      joinVerification: () async {
        validSession = false;
        return null;
      },
      probe: () async {
        probes++;
      },
    );
    check(probes == 0, 'old session must not probe new account');
  },
  'cancel during join prevents probe': () async {
    final warmup = StartupConnectionWarmup();
    var probes = 0;
    await warmup.start(
      canRun: () => true,
      prepare: () async {},
      joinVerification: () async {
        warmup.cancel();
        return null;
      },
      probe: () async {
        probes++;
      },
    );
    check(probes == 0, 'cancelled join must not probe');
  },
  'existing successful verification is sufficient': () async {
    var probes = 0;
    await StartupConnectionWarmup().start(
      canRun: () => true,
      prepare: () async {},
      joinVerification: () async => true,
      probe: () async {
        probes++;
      },
    );
    check(probes == 0, 'existing challenge should not duplicate probe');
  },
  'existing failed or changed verification never starts another': () async {
    var probes = 0;
    await StartupConnectionWarmup().start(
      canRun: () => true,
      prepare: () async {},
      joinVerification: () async => false,
      probe: () async {
        probes++;
      },
    );
    check(probes == 0, 'failure must not re-challenge');
  },
  'probe challenge uses delegated request once without own retry': () async {
    var requests = 0;
    final challengeReady = Completer<void>();
    final task = StartupConnectionWarmup().start(
      canRun: () => true,
      prepare: () async {},
      joinVerification: () async => null,
      probe: () async {
        requests++;
        await challengeReady.future;
      },
    );
    await Future<void>.delayed(Duration.zero);
    check(requests == 1, 'normal request starts without awaiting UI');
    challengeReady.complete();
    await task;
    check(requests == 1, 'coordinator has no retry loop');
  },
};

Future<void> main() async {
  for (final entry in startupWarmupSmokeTests.entries) {
    await entry.value();
    print('PASS: ${entry.key}');
  }
}
