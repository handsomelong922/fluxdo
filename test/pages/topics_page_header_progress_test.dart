import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/topics_page.dart';

void main() {
  test('quantizeMobileHeaderProgress only flips after threshold', () {
    expect(quantizeMobileHeaderProgress(0.0, threshold: 0.6), 0.0);
    expect(quantizeMobileHeaderProgress(0.59, threshold: 0.6), 0.0);
    expect(quantizeMobileHeaderProgress(0.6, threshold: 0.6), 1.0);
    expect(quantizeMobileHeaderProgress(1.0, threshold: 0.6), 1.0);
  });
}
