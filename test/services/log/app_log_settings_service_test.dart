import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/log/app_log_settings_service.dart';
import 'package:fluxdo/services/log/runtime_log_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    RuntimeLogSettings.configure(
      developerModeEnabled: false,
      appLogsEnabled: false,
      appLogEntryLimit: 100,
    );
  });

  test('defaults app logs to disabled for fresh installs', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    AppLogSettingsService.instance.initialize(prefs);

    expect(AppLogSettingsService.instance.enabled, isFalse);
    expect(RuntimeLogSettings.appLogsEnabled, isFalse);
    expect(AppLogSettingsService.instance.retainedEntryLimit, 100);
  });
}
