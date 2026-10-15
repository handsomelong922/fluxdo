import '../lib/services/cf_verification_metrics.dart';

final cfVerificationMetricsSmokeTests = <String, void Function()>{
  'disabled diagnostics neither sample the clock nor collect rounds': () {
    final metrics = CfVerificationMetrics(
      monotonicMicroseconds: () => throw StateError('clock must stay unused'),
    );
    metrics.start(1);
    metrics.foregroundPresented(1);
    _check(metrics.finish(1, CfVerificationOutcome.failed) == null);
    _check(metrics.snapshot.values.every((value) => value == 0));
  },
  'joined requests, repeated presentation and terminal callbacks count once':
      () {
        var now = 5000;
        final metrics = CfVerificationMetrics(monotonicMicroseconds: () => now)
          ..setEnabled(true)
          ..start(1);
        for (var i = 0; i < 5; i++) {
          metrics.start(1);
          metrics.foregroundPresented(1);
        }
        now += 2500000;
        final result = metrics.finish(1, CfVerificationOutcome.succeeded)!;
        _check(result['startedRounds'] == 1);
        _check(result['completedRounds'] == 1);
        _check(result['foregroundPresentations'] == 1);
        _check(result['waitMs'] == 2500);
        _check(result['succeededRounds'] == 1);
        _check(result['pendingRounds'] == 0);
        _check(metrics.finish(1, CfVerificationOutcome.failed) == null);
        metrics.start(1);
        _check(metrics.snapshot['startedRounds'] == 1);
      },
  'separate rounds aggregate success, cancellation, failure and monotonic wait':
      () {
        var now = 0;
        final metrics = CfVerificationMetrics(monotonicMicroseconds: () => now)
          ..setEnabled(true);
        final outcomes = CfVerificationOutcome.values;
        for (var i = 0; i < outcomes.length; i++) {
          metrics.start(i + 1);
          now += (i + 1) * 1000000;
          final result = metrics.finish(i + 1, outcomes[i])!;
          _check(result['outcome'] == outcomes[i].name);
          _check(result['waitMs'] == (i + 1) * 1000);
        }
        final result = metrics.snapshot;
        _check(result['startedRounds'] == 3 && result['completedRounds'] == 3);
        _check(result['succeededRounds'] == 1);
        _check(result['cancelledRounds'] == 1);
        _check(result['failedRounds'] == 1);
        _check(result['totalWaitMs'] == 6000);
        _check(result['meanWaitMs'] == 2000);
        _check(result['maxWaitMs'] == 3000);
        _check(result['foregroundPresentations'] == 0);
      },
  'unfinished rounds are pending, never fabricated terminal statistics': () {
    var now = 0;
    final metrics = CfVerificationMetrics(monotonicMicroseconds: () => now)
      ..setEnabled(true)
      ..start(1);
    now += 90000000;
    metrics.start(2);
    _check(metrics.snapshot['startedRounds'] == 1);
    _check(metrics.snapshot['pendingRounds'] == 1);
    _check(metrics.snapshot['completedRounds'] == 0);
    _check(metrics.snapshot['totalWaitMs'] == 0);
    _check(metrics.snapshot['failedRounds'] == 0);
  },
  'stale events cannot present or finish the next round': () {
    var now = 0;
    final metrics = CfVerificationMetrics(monotonicMicroseconds: () => now)
      ..setEnabled(true)
      ..start(1);
    metrics.finish(1, CfVerificationOutcome.succeeded);
    metrics.start(2);
    now += 4000000;
    metrics.foregroundPresented(1);
    _check(metrics.finish(1, CfVerificationOutcome.failed) == null);
    _check(metrics.finish(3, CfVerificationOutcome.failed) == null);
    _check(metrics.snapshot['foregroundPresentations'] == 0);
    _check(metrics.snapshot['pendingRounds'] == 1);
    _check(metrics.snapshot['completedRounds'] == 1);
    _check(
      metrics.finish(2, CfVerificationOutcome.cancelled)!['waitMs'] == 4000,
    );
  },
  'disabling clears all state and re-enabling ignores a partly observed round':
      () {
        var now = 0;
        final metrics = CfVerificationMetrics(monotonicMicroseconds: () => now)
          ..setEnabled(true)
          ..start(1)
          ..foregroundPresented(1)
          ..setEnabled(false);
        _check(metrics.snapshot.values.every((value) => value == 0));
        now += 9000000;
        metrics.setEnabled(true);
        metrics.foregroundPresented(1);
        _check(metrics.finish(1, CfVerificationOutcome.failed) == null);
        _check(metrics.snapshot.values.every((value) => value == 0));
        metrics.start(2);
        now += 1000000;
        _check(
          metrics.finish(2, CfVerificationOutcome.succeeded)!['waitMs'] == 1000,
        );
      },
  'repeated enable preserves the active observation': () {
    var now = 0;
    final metrics = CfVerificationMetrics(monotonicMicroseconds: () => now)
      ..setEnabled(true)
      ..start(1)
      ..setEnabled(true);
    now += 1000000;
    _check(
      metrics.finish(1, CfVerificationOutcome.succeeded)!['waitMs'] == 1000,
    );
  },
  'sub-millisecond precision is retained when calculating aggregates': () {
    var now = 0;
    final metrics = CfVerificationMetrics(monotonicMicroseconds: () => now)
      ..setEnabled(true);
    for (var round = 1; round <= 2; round++) {
      metrics.start(round);
      now += 1500;
      metrics.finish(round, CfVerificationOutcome.succeeded);
    }
    _check(metrics.snapshot['totalWaitMs'] == 3);
    _check(metrics.snapshot['meanWaitMs'] == 1);
    _check(metrics.snapshot['maxWaitMs'] == 1);
  },
  'many rounds keep a fixed diagnostic shape with no retained identities': () {
    var now = 0;
    final metrics = CfVerificationMetrics(monotonicMicroseconds: () => now)
      ..setEnabled(true);
    for (var round = 1; round <= 10000; round++) {
      metrics.start(round);
      now += 1000;
      final result = metrics.finish(round, CfVerificationOutcome.succeeded)!;
      _check(result.length == 12);
      _check(result.values.every((value) => value is int || value is String));
    }
    final copy = metrics.snapshot;
    copy['startedRounds'] = -1;
    _check(metrics.snapshot['startedRounds'] == 10000);
    _check(metrics.snapshot['completedRounds'] == 10000);
    _check(metrics.snapshot['totalWaitMs'] == 10000);
    _check(
      metrics.snapshot.keys.join(',') ==
          'startedRounds,completedRounds,pendingRounds,foregroundPresentations,'
              'succeededRounds,cancelledRounds,failedRounds,totalWaitMs,meanWaitMs,maxWaitMs',
    );
  },
};

void main() {
  for (final entry in cfVerificationMetricsSmokeTests.entries) {
    entry.value();
    print('PASS: ${entry.key}');
  }
  print(
    '${cfVerificationMetricsSmokeTests.length} verification metric checks passed',
  );
}

void _check(bool condition) {
  if (!condition) throw StateError('Verification metric expectation failed');
}
