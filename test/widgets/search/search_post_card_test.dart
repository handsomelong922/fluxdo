import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/app_localizations.dart';
import 'package:fluxdo/models/search_result.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/utils/time_utils.dart';
import 'package:fluxdo/widgets/search/search_post_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('SearchPostCard keeps home-style meta info on the right side', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final createdAt = DateTime.now().subtract(const Duration(days: 1));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          categoryMapProvider.overrideWithValue(const AsyncValue.data({})),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SearchPostCard(
              post: SearchPost(
                id: 1,
                username: 'tester',
                avatarTemplate: '/user_avatar/example/{size}/1.png',
                createdAt: createdAt,
                likeCount: 5,
                blurb: '<p>搜索摘要正文</p>',
                postNumber: 3,
                topic: SearchTopic(
                  id: 9,
                  title: '搜索结果标题',
                  slug: 'search-topic',
                  tags: const [Tag(id: 1, name: 'flutter')],
                  postsCount: 12,
                  views: 99,
                  closed: false,
                  archived: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('搜索结果标题'), findsOneWidget);
    expect(find.text('搜索摘要正文'), findsOneWidget);
    expect(find.text('#3'), findsNothing);
    expect(find.text('11'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text(TimeUtils.formatRelativeTime(createdAt)), findsOneWidget);
  });
}
