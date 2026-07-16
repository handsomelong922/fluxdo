import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/browser_trust_coordinator.dart';

void main() {
  test('automatic browser trust recovery remains fully background', () {
    expect(forceForegroundForAutomaticBrowserTrustRecovery, isFalse);
  });
}
