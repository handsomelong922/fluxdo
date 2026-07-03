import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/log/runtime_log_settings.dart';

void main() {
  tearDown(() {
    RuntimeLogSettings.configure(
      developerModeEnabled: false,
      appLogsEnabled: false,
      appLogEntryLimit: 100,
    );
  });

  test('drops diagnostics by default when app logs are off', () {
    RuntimeLogSettings.configure(
      developerModeEnabled: false,
      appLogsEnabled: false,
    );

    expect(
      RuntimeLogSettings.shouldPersistDiagnosticEvent(level: 'info'),
      isFalse,
    );
    expect(
      RuntimeLogSettings.shouldPersistDiagnosticEvent(level: 'warning'),
      isFalse,
    );
  });

  test('drops info request persistence by default', () {
    RuntimeLogSettings.configure(
      developerModeEnabled: false,
      appLogsEnabled: false,
    );

    expect(
      RuntimeLogSettings.shouldPersistRequestLog(
        level: 'info',
        isSilent: false,
      ),
      isFalse,
    );
    expect(
      RuntimeLogSettings.shouldPersistRequestLog(level: 'info', isSilent: true),
      isFalse,
    );
    expect(
      RuntimeLogSettings.shouldPersistRequestLog(
        level: 'warning',
        isSilent: true,
      ),
      isFalse,
    );
  });

  test('keeps verbose diagnostics in developer mode', () {
    RuntimeLogSettings.configure(
      developerModeEnabled: true,
      appLogsEnabled: true,
    );

    expect(
      RuntimeLogSettings.shouldPersistDiagnosticEvent(level: 'info'),
      isTrue,
    );
    expect(
      RuntimeLogSettings.shouldPersistRequestLog(
        level: 'debug',
        isSilent: true,
      ),
      isTrue,
    );
  });

  test('disabling app logs suppresses request and diagnostic persistence', () {
    RuntimeLogSettings.configure(
      developerModeEnabled: true,
      appLogsEnabled: false,
    );

    expect(
      RuntimeLogSettings.shouldPersistDiagnosticEvent(level: 'error'),
      isFalse,
    );
    expect(
      RuntimeLogSettings.shouldPersistRequestLog(
        level: 'warning',
        isSilent: false,
      ),
      isFalse,
    );
  });
}
