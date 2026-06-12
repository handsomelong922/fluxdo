import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/app_localizations.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/utils/time_utils.dart';
import 'package:fluxdo/widgets/topic/topic_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('TopicCard shows topic created time instead of last reply time', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final createdAt = DateTime.now().subtract(const Duration(days: 2));
    final lastPostedAt = DateTime.now().subtract(const Duration(minutes: 2));

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
            body: TopicCard(
              topic: Topic(
                id: 1,
                title: '测试话题',
                slug: 'test-topic',
                postsCount: 2,
                replyCount: 1,
                views: 0,
                likeCount: 0,
                createdAt: createdAt,
                lastPostedAt: lastPostedAt,
                lastPosterUsername: 'tester',
                categoryId: '1',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text(TimeUtils.formatRelativeTime(createdAt)), findsOneWidget);
    expect(find.text(TimeUtils.formatRelativeTime(lastPostedAt)), findsNothing);
  });
}
