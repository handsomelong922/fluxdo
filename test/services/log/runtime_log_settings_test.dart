import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/log/runtime_log_settings.dart';

void main() {
  tearDown(() {
    RuntimeLogSettings.configure(
      developerModeEnabled: false,
      appLogsEnabled: true,
      appLogEntryLimit: 150,
    );
  });

  test('drops verbose info diagnostics by default', () {
    RuntimeLogSettings.configure(developerModeEnabled: false);

    expect(
      RuntimeLogSettings.shouldPersistDiagnosticEvent(level: 'info'),
      isFalse,
    );
    expect(
      RuntimeLogSettings.shouldPersistDiagnosticEvent(level: 'warning'),
      isTrue,
    );
  });

  test('drops info request persistence by default', () {
    RuntimeLogSettings.configure(developerModeEnabled: false);

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
      isTrue,
    );
  });

  test('keeps verbose diagnostics in developer mode', () {
    RuntimeLogSettings.configure(developerModeEnabled: true);

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
