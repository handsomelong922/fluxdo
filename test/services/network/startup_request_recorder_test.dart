import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/startup_request_recorder.dart';

void main() {
  tearDown(() {
    StartupRequestRecorder.instance.clear();
  });

  test('records request start relative to app initialization time', () {
    StartupRequestRecorder.ensureInitialized();
    final startedAtMillis = DateTime.now().millisecondsSinceEpoch;

    final record = StartupRequestRecorder.instance.record(
      startedAtMillis: startedAtMillis,
      durationMs: 12,
      method: 'GET',
      url: 'https://linux.do/',
      path: '/',
      statusCode: 200,
      level: 'info',
      priority: 'high',
      isSilent: false,
      networkAdapter: 'rhttp',
      errorType: null,
    );

    expect(record.relativeStartMs, greaterThanOrEqualTo(0));
    expect(record.toSummaryLine(), contains('GET'));
    expect(record.toSummaryLine(), contains('/'));
  });
}
