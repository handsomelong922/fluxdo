import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/app_localizations.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/pages/topic_detail_page/topic_detail_page.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/progress_gesture_action_meta.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/topic_detail_overlay.dart';
import 'package:fluxdo/widgets/topic/topic_progress.dart';

void main() {
  group('shouldShowTopicTimelineProgress', () {
    test('keeps timeline jump in normal view only', () {
      expect(
        shouldShowTopicTimelineProgress(
          isNestedView: false,
          isTopLevelMode: false,
        ),
        isTrue,
      );
      expect(
        shouldShowTopicTimelineProgress(
          isNestedView: true,
          isTopLevelMode: false,
        ),
        isFalse,
      );
      expect(
        shouldShowTopicTimelineProgress(
          isNestedView: false,
          isTopLevelMode: true,
        ),
        isFalse,
      );
    });
  });

  group('TopicDetailOverlay', () {
    testWidgets('shows progress control by default', (tester) async {
      await tester.pumpWidget(_buildApp(showProgress: true));

      expect(find.byType(TopicProgress), findsOneWidget);
    });

    testWidgets('hides progress control when disabled', (tester) async {
      await tester.pumpWidget(_buildApp(showProgress: false));

      expect(find.byType(TopicProgress), findsNothing);
    });

    testWidgets('keeps progress tap callback while wrapped by gestures', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        _buildApp(showProgress: true, onProgressTap: () => tapped = true),
      );

      await tester.tap(find.byType(TopicProgress));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('dispatches progress swipe action', (tester) async {
      ProgressGestureAction? action;
      await tester.pumpWidget(
        _buildApp(showProgress: true, onProgressAction: (a) => action = a),
      );

      await tester.drag(find.byType(TopicProgress), const Offset(-90, 0));
      await tester.pumpAndSettle();

      expect(action, ProgressGestureAction.nextPost);
    });
  });
}

Widget _buildApp({
  required bool showProgress,
  VoidCallback? onProgressTap,
  ValueChanged<ProgressGestureAction>? onProgressAction,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: TopicDetailOverlay(
        showBottomBar: true,
        isLoggedIn: false,
        currentStreamIndex: 1,
        totalCount: 2,
        detail: _detail(),
        onScrollToTop: () {},
        onShare: () {},
        onBookmark: () {},
        onBookmarkLongPress: () {},
        onReply: () {},
        onProgressTap: onProgressTap ?? () {},
        onProgressAction: onProgressAction,
        showProgress: showProgress,
      ),
    ),
  );
}

TopicDetail _detail() {
  return TopicDetail(
    id: 42,
    title: 'Topic',
    slug: 'topic',
    postsCount: 2,
    postStream: PostStream(posts: const [], stream: const [101, 102]),
    categoryId: 1,
    closed: false,
    archived: false,
  );
}
