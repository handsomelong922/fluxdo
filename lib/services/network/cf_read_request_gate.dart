import 'dart:async';

enum CfReadGateResult { notNeeded, resumed, blocked, cancelled }

/// Per-request deadline for waiting on already active verification rounds.
///
/// This never starts verification or replays a request. Only foreground GET and
/// HEAD requests may wait; writes and background polling keep failing fast.
/// Adjacent rounds share one deadline, including time spent back in the normal
/// scheduler queue. Cancelling a waiter never cancels the shared verification.
/// Once this request times out, later verification cannot revive its admission.
class CfReadRequestGate {
  CfReadRequestGate({Stopwatch? stopwatch})
    : _waitingTime = stopwatch ?? Stopwatch();

  final Stopwatch _waitingTime;
  bool _deadlineExpired = false;

  Future<CfReadGateResult> wait({
    required String method,
    required bool isSilent,
    required bool skipCfBlock,
    required bool Function() isVerifying,
    required Future<bool?> Function() waitForVerification,
    Future<void>? whenCancelled,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    if (skipCfBlock) return CfReadGateResult.notNeeded;
    if (_deadlineExpired) return CfReadGateResult.blocked;
    if (!isVerifying()) return CfReadGateResult.notNeeded;
    final safeRead =
        method.toUpperCase() == 'GET' || method.toUpperCase() == 'HEAD';
    if (!safeRead || isSilent) return CfReadGateResult.blocked;
    _waitingTime.start();

    try {
      do {
        final remaining = timeout - _waitingTime.elapsed;
        if (remaining <= Duration.zero) return _expireDeadline();
        final result = await Future.any<CfReadGateResult>([
          waitForVerification().then(
            (ready) => ready == true
                ? CfReadGateResult.resumed
                : CfReadGateResult.blocked,
          ),
          if (whenCancelled != null)
            whenCancelled.then((_) => CfReadGateResult.cancelled),
        ]).timeout(remaining, onTimeout: _expireDeadline);
        if (result != CfReadGateResult.resumed) return result;
        // A different request may start the next round before this waiter
        // resumes. Join it within the original deadline, never start our own.
      } while (isVerifying());
      return CfReadGateResult.resumed;
    } catch (_) {
      return CfReadGateResult.blocked;
    }
  }

  CfReadGateResult _expireDeadline() {
    // Timer rounds sub-millisecond durations down on some platforms. Preserve
    // its terminal decision even if Stopwatch still has a fractional remainder.
    _deadlineExpired = true;
    return CfReadGateResult.blocked;
  }
}
