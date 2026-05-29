import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/cdk_page.dart';

void main() {
  group('isTrustedCdkWebViewHost', () {
    test('allows CDK payment and auth hosts inside the CDK WebView', () {
      expect(isTrustedCdkWebViewHost('cdk.linux.do'), isTrue);
      expect(isTrustedCdkWebViewHost('credit.linux.do'), isTrue);
      expect(isTrustedCdkWebViewHost('connect.linux.do'), isTrue);
      expect(isTrustedCdkWebViewHost('linux.do'), isTrue);
    });

    test('allows linux.do subdomains but rejects lookalike domains', () {
      expect(isTrustedCdkWebViewHost('pay.credit.linux.do'), isTrue);
      expect(isTrustedCdkWebViewHost('example.com'), isFalse);
      expect(isTrustedCdkWebViewHost('credit.linux.do.example.com'), isFalse);
      expect(isTrustedCdkWebViewHost('evil-linux.do'), isFalse);
    });
  });
}
