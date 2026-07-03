import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/startup_request_recorder.dart';

void main() {
  tearDown(() {
    StartupRequestRecorder.instance.clear();
    StartupRequestRecorder.instance.configure(
      enabled: true,
      maxRecords: 150,
      clearWhenDisabled: false,
    );
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

  test('does not retain records when disabled', () {
    StartupRequestRecorder.instance.configure(
      enabled: false,
      maxRecords: 150,
      clearWhenDisabled: true,
    );

    StartupRequestRecorder.instance.record(
      startedAtMillis: DateTime.now().millisecondsSinceEpoch,
      durationMs: 20,
      method: 'GET',
      url: 'https://linux.do/latest.json',
      path: '/latest.json',
      statusCode: 200,
      level: 'info',
      priority: 'high',
      isSilent: false,
      networkAdapter: 'rhttp',
      errorType: null,
    );

    expect(StartupRequestRecorder.instance.records, isEmpty);
  });

  test('trims records to configured max size', () {
    StartupRequestRecorder.instance.configure(
      enabled: true,
      maxRecords: 50,
      clearWhenDisabled: false,
    );

    for (var index = 0; index < 80; index++) {
      StartupRequestRecorder.instance.record(
        startedAtMillis: DateTime.now().millisecondsSinceEpoch,
        durationMs: index,
        method: 'GET',
        url: 'https://linux.do/t/$index/1.json',
        path: '/t/$index/1.json',
        statusCode: 200,
        level: 'info',
        priority: 'low',
        isSilent: true,
        networkAdapter: 'rhttp',
        errorType: null,
      );
    }

    expect(StartupRequestRecorder.instance.records.length, 50);
  });
}
