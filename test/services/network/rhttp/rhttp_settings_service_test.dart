import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluxdo/config/app_build_profile.dart';
import 'package:fluxdo/services/network/doh/network_settings_service.dart';
import 'package:fluxdo/services/network/proxy/proxy_settings_service.dart';
import 'package:fluxdo/services/network/rhttp/rhttp_settings_service.dart';

void main() {
  group('RhttpSettingsService forceDisable', () {
    late SharedPreferences prefs;
    late RhttpSettingsService rhttp;

    setUp(() async {
      rhttp = RhttpSettingsService.instance;
      rhttp.resetForTest();

      SharedPreferences.setMockInitialValues({
        'rhttp_enabled': true,
        'rhttp_mode': 0,
      });
      prefs = await SharedPreferences.getInstance();
    });

    test('forceDisable 不修改 SharedPreferences', () async {
      await rhttp.initialize(prefs);
      expect(prefs.getBool('rhttp_enabled'), true);

      await rhttp.forceDisable();

      expect(
        prefs.getBool('rhttp_enabled'),
        true,
        reason: 'forceDisable 不应覆盖用户的偏好设置',
      );
    });

    test('initialize respects build profile availability', () async {
      await rhttp.initialize(prefs);

      expect(rhttp.current.enabled, AppNetworkProfile.supportsRhttp);
      expect(rhttp.current.forceDisabled, !AppNetworkProfile.supportsRhttp);
      expect(
        rhttp.shouldUseRhttp(_networkSettings(), const ProxySettings()),
        AppNetworkProfile.supportsRhttp,
      );
    });

    test('forceDisable 后 enabled 保持当前 profile 的可用状态', () async {
      await rhttp.initialize(prefs);
      await rhttp.forceDisable();

      expect(rhttp.current.enabled, AppNetworkProfile.supportsRhttp);
      expect(rhttp.current.forceDisabled, true);
    });

    test('forceDisable 后 shouldUseRhttp 返回 false', () async {
      await rhttp.initialize(prefs);
      await rhttp.forceDisable();

      expect(
        rhttp.shouldUseRhttp(_networkSettings(), const ProxySettings()),
        false,
      );
    });

    test('setEnabled 和 setMode 不改变 forceDisabled', () async {
      await rhttp.initialize(prefs);
      await rhttp.forceDisable();

      await rhttp.setEnabled(false);
      expect(rhttp.current.forceDisabled, true);

      await rhttp.setEnabled(true);
      expect(rhttp.current.forceDisabled, true);

      await rhttp.setMode(RhttpMode.proxyOnly);
      expect(rhttp.current.forceDisabled, true);
    });

    test('重新 initialize 后 forceDisabled 恢复为 false', () async {
      await rhttp.initialize(prefs);
      await rhttp.forceDisable();
      expect(rhttp.current.forceDisabled, true);

      rhttp.resetForTest();
      SharedPreferences.setMockInitialValues({
        'rhttp_enabled': true,
        'rhttp_mode': 0,
      });
      final freshPrefs = await SharedPreferences.getInstance();

      await rhttp.initialize(freshPrefs);

      expect(rhttp.current.enabled, AppNetworkProfile.supportsRhttp);
      expect(rhttp.current.forceDisabled, !AppNetworkProfile.supportsRhttp);
    });
  });
}

NetworkSettings _networkSettings() {
  return NetworkSettings(
    dohEnabled: false,
    selectedServerUrl: 'https://dns.google/dns-query',
    customServers: const [],
    proxyPort: null,
  );
}
