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
          ),
          isTrue,
        );
      },
    );

    test('swipe back is enabled only for mobile top-level topic page', () {
      expect(
        shouldEnableTopicSwipeBack(
          embeddedMode: false,
          isSearchMode: false,
          isOnAiPage: false,
          isMobile: true,
        ),
        isTrue,
      );
      expect(
        shouldEnableTopicSwipeBack(
          embeddedMode: false,
          isSearchMode: true,
          isOnAiPage: false,
          isMobile: true,
        ),
        isFalse,
      );
      expect(
        shouldEnableTopicSwipeBack(
          embeddedMode: false,
          isSearchMode: false,
          isOnAiPage: true,
          isMobile: true,
        ),
        isFalse,
      );
      expect(
        shouldEnableTopicSwipeBack(
          embeddedMode: true,
          isSearchMode: false,
          isOnAiPage: false,
          isMobile: true,
        ),
        isFalse,
      );
    });

    test('swipe back requires a mostly horizontal rightward drag', () {
      expect(shouldTriggerTopicSwipeBack(const Offset(80, 12)), isTrue);
      expect(shouldTriggerTopicSwipeBack(const Offset(56, 4)), isFalse);
      expect(shouldTriggerTopicSwipeBack(const Offset(80, 72)), isFalse);
      expect(shouldRejectTopicSwipeBack(const Offset(-16, 0)), isTrue);
      expect(shouldRejectTopicSwipeBack(const Offset(8, 64)), isTrue);
      expect(shouldRejectTopicSwipeBack(const Offset(36, 18)), isFalse);
    });
  });
}
