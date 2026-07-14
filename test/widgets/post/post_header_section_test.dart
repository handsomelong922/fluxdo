import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/app_localizations.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/widgets/post/post_item/widgets/post_header.dart';
import 'package:fluxdo/widgets/post/post_item/widgets/post_header_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('帖头头像缓存会随主题切换失效', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final post = _post();

    final themeMode = ValueNotifier(ThemeMode.light);
    addTearDown(themeMode.dispose);

    final app = ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeMode,
        builder: (context, mode, _) => MaterialApp(
          navigatorKey: navigatorKey,
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: mode,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PostHeaderSection(
              post: post,
              topicId: 42,
              isTopicOwner: true,
              showStamp: false,
              padding: EdgeInsets.zero,
              onJumpToPost: null,
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app);
    await tester.pump();
    expect(
      tester.widget<PostAvatar>(find.byType(PostAvatar)).theme.brightness,
      Brightness.light,
    );

    themeMode.value = ThemeMode.dark;
    await tester.pumpAndSettle();
    expect(
      tester.widget<PostAvatar>(find.byType(PostAvatar)).theme.brightness,
      Brightness.dark,
    );
  });
}

Post _post() {
  final createdAt = DateTime.utc(2026, 7, 14, 12);
  return Post(
    id: 101,
    topicId: 42,
    name: 'Tester',
    username: 'tester',
    avatarTemplate: '',
    cooked: '<p>content</p>',
    postNumber: 1,
    postType: 1,
    updatedAt: createdAt,
    createdAt: createdAt,
    likeCount: 0,
    replyCount: 0,
  );
}
