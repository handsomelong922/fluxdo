import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/link_launcher.dart';

void main() {
  group('isCdkUrlString', () {
    test('recognizes cdk.linux.do http variants', () {
      expect(isCdkUrlString('https://cdk.linux.do'), isTrue);
      expect(isCdkUrlString('https://cdk.linux.do/abc?code=1'), isTrue);
      expect(isCdkUrlString('//cdk.linux.do/redeem'), isTrue);
    });

    test('does not match other hosts', () {
      expect(isCdkUrlString('https://linux.do/t/1'), isFalse);
      expect(isCdkUrlString('https://example.com/cdk.linux.do'), isFalse);
      expect(isCdkUrlString('/t/1'), isFalse);
    });
  });
}
