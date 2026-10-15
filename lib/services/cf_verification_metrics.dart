/// Terminal state of the coordinator, after its existing readiness/cleanup gate.
/// Success means the verification page and cleanup finished, not that a person
/// clicked a checkbox or that a subsequent business request succeeded.
enum CfVerificationOutcome { succeeded, cancelled, failed }

/// Constant-space, opt-in diagnostics for actual coordinator rounds.
///
/// There is no per-request history, identifying data, persistence or timer task.
/// Disabling diagnostics clears everything. Enabling midway through a round
/// does not collect a partial duration; only the next observed start counts.
class CfVerificationMetrics {
  CfVerificationMetrics({int Function()? monotonicMicroseconds})
    : _now = monotonicMicroseconds ?? _monotonicMicroseconds;

  static final _clock = Stopwatch()..start();
  static int _monotonicMicroseconds() => _clock.elapsedMicroseconds;

  final int Function() _now;
  bool _enabled = false;
  int? _latestRound;
  int? _activeRound;
  int? _startedAt;
  bool _foregroundRecorded = false;
  int _started = 0;
  int _completed = 0;
  int _foreground = 0;
  int _succeeded = 0;
  int _cancelled = 0;
  int _failed = 0;
  int _totalWaitUs = 0;
  int _maxWaitUs = 0;

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    _latestRound = null;
    _activeRound = null;
    _startedAt = null;
    _foregroundRecorded = false;
    _started = _completed = _foreground = 0;
    _succeeded = _cancelled = _failed = 0;
    _totalWaitUs = _maxWaitUs = 0;
  }

  void start(int round) {
    if (!_enabled || _activeRound != null) return;
    if (_latestRound != null && round <= _latestRound!) return;
    _latestRound = _activeRound = round;
    _startedAt = _now();
    _foregroundRecorded = false;
    _started++;
  }

  /// A rendered foreground panel, at most once per round. This deliberately
  /// does not count requests to promote, rebuilds, reloads or checkbox actions.
  void foregroundPresented(int round) {
    if (!_enabled || round != _activeRound || _foregroundRecorded) return;
    _foregroundRecorded = true;
    _foreground++;
  }

  /// Returns only primitive, non-identifying fields for the existing logger.
  /// Duplicate and late callbacks cannot complete or mutate another round.
  Map<String, Object>? finish(int round, CfVerificationOutcome outcome) {
    if (!_enabled || round != _activeRound) return null;
    final elapsed = _now() - _startedAt!;
    final elapsedUs = elapsed < 0 ? 0 : elapsed;
    _activeRound = null;
    _startedAt = null;
    _completed++;
    _totalWaitUs += elapsedUs;
    if (elapsedUs > _maxWaitUs) _maxWaitUs = elapsedUs;
    switch (outcome) {
      case CfVerificationOutcome.succeeded:
        _succeeded++;
      case CfVerificationOutcome.cancelled:
        _cancelled++;
      case CfVerificationOutcome.failed:
        _failed++;
    }
    return {'outcome': outcome.name, 'waitMs': elapsedUs ~/ 1000, ...snapshot};
  }

  /// Totals for this continuous enabled interval. Waiting-time aggregates
  /// include completed rounds only; pending rounds remain visibly incomplete.
  Map<String, Object> get snapshot => {
    'startedRounds': _started,
    'completedRounds': _completed,
    'pendingRounds': _activeRound == null ? 0 : 1,
    'foregroundPresentations': _foreground,
    'succeededRounds': _succeeded,
    'cancelledRounds': _cancelled,
    'failedRounds': _failed,
    'totalWaitMs': _totalWaitUs ~/ 1000,
    'meanWaitMs': _completed == 0 ? 0 : _totalWaitUs ~/ _completed ~/ 1000,
    'maxWaitMs': _maxWaitUs ~/ 1000,
  };
}
