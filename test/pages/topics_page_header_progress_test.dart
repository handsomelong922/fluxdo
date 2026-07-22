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

  group('homeScrollToTopStagingOffset', () {
    test('把远距离回顶限制在两个 viewport 内', () {
      expect(
        homeScrollToTopStagingOffset(
          currentOffset: 5000,
          minScrollExtent: 0,
          maxScrollExtent: 6000,
          viewportDimension: 800,
        ),
        1600,
      );
    });

    test('距离顶部不超过两个 viewport 时保持单段动画', () {
      expect(
        homeScrollToTopStagingOffset(
          currentOffset: 1500,
          minScrollExtent: 0,
          maxScrollExtent: 6000,
          viewportDimension: 800,
        ),
        isNull,
      );
    });

    test('以实际最小滚动范围计算 staging offset', () {
      expect(
        homeScrollToTopStagingOffset(
          currentOffset: 5000,
          minScrollExtent: 100,
          maxScrollExtent: 6000,
          viewportDimension: 800,
        ),
        1700,
      );
    });

    test('viewport 无效时不执行 staging', () {
      expect(
        homeScrollToTopStagingOffset(
          currentOffset: 5000,
          minScrollExtent: 0,
          maxScrollExtent: 6000,
          viewportDimension: 0,
        ),
        isNull,
      );
    });
  });
}
