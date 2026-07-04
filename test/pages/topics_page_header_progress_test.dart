import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/topics_page.dart';

void main() {
  test('quantizeMobileHeaderProgress only flips after threshold', () {
    expect(quantizeMobileHeaderProgress(0.0, threshold: 0.6), 0.0);
    expect(quantizeMobileHeaderProgress(0.59, threshold: 0.6), 0.0);
    expect(quantizeMobileHeaderProgress(0.6, threshold: 0.6), 1.0);
    expect(quantizeMobileHeaderProgress(1.0, threshold: 0.6), 1.0);
  });

  test('resolveMobileHomeBarVisibility hides and restores with hysteresis', () {
    expect(
      resolveMobileHomeBarVisibility(
        currentVisibility: 1.0,
        pixels: 120,
        accumulatedDelta: 20,
      ),
      1.0,
    );
    expect(
      resolveMobileHomeBarVisibility(
        currentVisibility: 1.0,
        pixels: 120,
        accumulatedDelta: 36,
      ),
      0.0,
    );
    expect(
      resolveMobileHomeBarVisibility(
        currentVisibility: 0.0,
        pixels: 120,
        accumulatedDelta: -20,
      ),
      0.0,
    );
    expect(
      resolveMobileHomeBarVisibility(
        currentVisibility: 0.0,
        pixels: 120,
        accumulatedDelta: -36,
      ),
      1.0,
    );
    expect(
      resolveMobileHomeBarVisibility(
        currentVisibility: 0.0,
        pixels: 0,
        accumulatedDelta: 99,
      ),
      1.0,
    );
  });
}
