import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/app_localizations.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/pages/topic_detail_page/topic_detail_page.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/topic_detail_overlay.dart';
import 'package:fluxdo/widgets/common/glass_action_button.dart';
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

    testWidgets('uses the glass reply action when logged in', (tester) async {
      await tester.pumpWidget(_buildApp(showProgress: true, isLoggedIn: true));

      expect(find.byType(GlassActionButton), findsOneWidget);
      expect(find.byIcon(Icons.reply_rounded), findsOneWidget);
      expect(
        tester.getSize(find.byType(GlassActionButton)),
        const Size(56, 56),
      );
    });
  });
}

Widget _buildApp({required bool showProgress, bool isLoggedIn = false}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: TopicDetailOverlay(
        showBottomBar: true,
        isLoggedIn: isLoggedIn,
        currentStreamIndex: 1,
        totalCount: 2,
        detail: _detail(),
        onScrollToTop: () {},
        onShare: () {},
        onBookmark: () {},
        onBookmarkLongPress: () {},
        onReply: () {},
        onProgressTap: () {},
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
