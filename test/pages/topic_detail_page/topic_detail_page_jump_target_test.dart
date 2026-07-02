import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/topic_detail_page/topic_detail_page.dart';

void main() {
  group('topic detail jump target helpers', () {
    test('tree view never waits on the flat post-window skeleton gate', () {
      expect(
        shouldBlockForFlatJumpTarget(
          isNestedView: true,
          jumpTargetPostNumber: 88,
          hasLoadedPosts: true,
          firstLoadedPostNumber: 1,
          lastLoadedPostNumber: 20,
        ),
        isFalse,
      );
    });

    test('flat view still waits when the target is outside loaded posts', () {
      expect(
        shouldBlockForFlatJumpTarget(
          isNestedView: false,
          jumpTargetPostNumber: 88,
          hasLoadedPosts: true,
          firstLoadedPostNumber: 1,
          lastLoadedPostNumber: 20,
        ),
        isTrue,
      );
    });

    test('external post target becomes the initial pending nested target', () {
      expect(
        resolveInitialPendingNestedPostNumber(
          isNestedView: true,
          scrollToPostNumber: 42,
          restoredNestedView: false,
          restoredPostNumber: null,
        ),
        42,
      );
    });

    test(
      'home preview entry without explicit target does not restore nested jump',
      () {
        expect(
          resolveInitialPendingNestedPostNumber(
            isNestedView: true,
            scrollToPostNumber: null,
            restoredNestedView: true,
            restoredPostNumber: 42,
            hasInitialPreview: true,
          ),
          isNull,
        );
      },
    );

    test('preview entry preserves explicit nested jump target', () {
      expect(
        resolveInitialPendingNestedPostNumber(
          isNestedView: true,
          scrollToPostNumber: 42,
          restoredNestedView: true,
          restoredPostNumber: 9,
          hasInitialPreview: true,
        ),
        42,
      );
    });

    test('preview entry defaults to flat view even when nested preference is on', () {
      expect(
        resolveInitialNestedView(
          initialNestedView: null,
          restoredNestedView: true,
          preferenceNestedView: true,
          hasInitialPreview: true,
        ),
        isFalse,
      );
    });

    test('restored nested state remains the fallback pending target', () {
      expect(
        resolveInitialPendingNestedPostNumber(
          isNestedView: true,
          scrollToPostNumber: null,
          restoredNestedView: true,
          restoredPostNumber: 128,
        ),
        128,
      );
    });

    test(
      'explicit nested view from link overrides saved and default state',
      () {
        expect(
          resolveInitialNestedView(
            initialNestedView: true,
            restoredNestedView: false,
            preferenceNestedView: false,
            hasInitialPreview: true,
          ),
          isTrue,
        );
      },
    );
  });
}
