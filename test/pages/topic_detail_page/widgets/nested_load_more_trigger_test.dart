import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/nested_load_more_trigger.dart';

void main() {
  group('NestedLoadMoreTrigger', () {
    test('arms near bottom before triggering on continued downward scroll', () {
      final trigger = NestedLoadMoreTrigger();

      expect(
        trigger.update(
          pixels: 1640,
          maxScrollExtent: 2000,
          hasMoreRoots: true,
          isLoadingMore: false,
        ),
        isFalse,
      );
      expect(trigger.isArmed, isTrue);

      expect(
        trigger.update(
          pixels: 1643,
          maxScrollExtent: 2000,
          hasMoreRoots: true,
          isLoadingMore: false,
        ),
        isFalse,
      );
      expect(trigger.isArmed, isTrue);

      expect(
        trigger.update(
          pixels: 1648,
          maxScrollExtent: 2000,
          hasMoreRoots: true,
          isLoadingMore: false,
        ),
        isTrue,
      );
      expect(trigger.isArmed, isFalse);
    });

    test('resets when leaving load-more region', () {
      final trigger = NestedLoadMoreTrigger();

      expect(
        trigger.update(
          pixels: 1640,
          maxScrollExtent: 2000,
          hasMoreRoots: true,
          isLoadingMore: false,
        ),
        isFalse,
      );
      expect(trigger.isArmed, isTrue);

      expect(
        trigger.update(
          pixels: 1200,
          maxScrollExtent: 2000,
          hasMoreRoots: true,
          isLoadingMore: false,
        ),
        isFalse,
      );
      expect(trigger.isArmed, isFalse);
    });

    test('does not trigger while loading or without more roots', () {
      final trigger = NestedLoadMoreTrigger();

      expect(
        trigger.update(
          pixels: 1640,
          maxScrollExtent: 2000,
          hasMoreRoots: false,
          isLoadingMore: false,
        ),
        isFalse,
      );
      expect(trigger.isArmed, isFalse);

      expect(
        trigger.update(
          pixels: 1648,
          maxScrollExtent: 2000,
          hasMoreRoots: true,
          isLoadingMore: true,
        ),
        isFalse,
      );
      expect(trigger.isArmed, isFalse);
    });
  });
}
