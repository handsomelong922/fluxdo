import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/link_launcher.dart';

void main() {
  group('isInternalUrlString', () {
    test('accepts linux.do topic links with malformed referral spacing', () {
      expect(
        isInternalUrlString('https://linux.do/t/topic/2293666?u = bbrother'),
        isTrue,
      );
    });

    test('accepts nested and canonical linux.do topic links', () {
      expect(
        isInternalUrlString('https://linux.do/n/topic/388420?sort=old'),
        isTrue,
      );
      expect(isInternalUrlString('https://linux.do/topic/388420'), isTrue);
    });
  });

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
