import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/vpn_auto_toggle_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('VpnAutoToggleService suppression intent', () {
    late VpnAutoToggleService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'vpn_auto_toggle_enabled': true});
      service = VpnAutoToggleService.instance;
      service.initialize(await SharedPreferences.getInstance());
    });

    test('records DOH restore intent without touching enabled state', () async {
      final before = service.suppressionNotifier.value;

      await service.setDohSuppressed(true);

      expect(service.isDohSuppressed, isTrue);
      expect(service.suppressionNotifier.value, before + 1);

      await service.setDohSuppressed(false);

      expect(service.isDohSuppressed, isFalse);
      expect(service.suppressionNotifier.value, before + 2);
    });

    test('records proxy restore intent', () async {
      await service.setProxySuppressed(true);

      expect(service.isProxySuppressed, isTrue);

      await service.setProxySuppressed(false);

      expect(service.isProxySuppressed, isFalse);
    });
  });
}
