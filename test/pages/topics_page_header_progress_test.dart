import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/topics_page.dart';

void main() {
  test('quantizeMobileHeaderProgress only flips after threshold', () {
    expect(quantizeMobileHeaderProgress(0.0, threshold: 0.6), 0.0);
    expect(quantizeMobileHeaderProgress(0.59, threshold: 0.6), 0.0);
    expect(quantizeMobileHeaderProgress(0.6, threshold: 0.6), 1.0);
    expect(quantizeMobileHeaderProgress(1.0, threshold: 0.6), 1.0);
  });

  test(
    'homeLoadMoreTriggerDistance prefetches before the footer is reached',
    () {
      expect(homeLoadMoreTriggerDistance(320), 720);
      expect(homeLoadMoreTriggerDistance(800), closeTo(1400, 0.001));
      expect(homeLoadMoreTriggerDistance(1400), 1800);
    },
  );
}
