import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/personal_topic_bar_settings.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/topic_bottom_bar.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/topic_detail_overlay.dart';
import 'package:fluxdo/providers/personal_topic_bar_preferences_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Widget host(Widget child) => ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: TranslationProvider(
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocaleUtils.supportedLocales,
        home: child,
      ),
    ),
  );

  testWidgets('真实底栏默认顺序与偏好更新一致，浏览器入口已移出底栏', (tester) async {
    await tester.pumpWidget(host(const Scaffold(body: TopicBottomBar())));
    final bar = find.byType(TopicBottomBar);
    final container = ProviderScope.containerOf(tester.element(bar));
    double x(TopicBarAction action) =>
        tester.getCenter(find.byKey(ValueKey('topic-bar-${action.name}'))).dx;
    expect(x(TopicBarAction.scrollToTop), lessThan(x(TopicBarAction.filter)));
    expect(x(TopicBarAction.filter), lessThan(x(TopicBarAction.share)));
    expect(x(TopicBarAction.share), lessThan(x(TopicBarAction.bookmark)));
    expect(find.byIcon(Symbols.language_rounded), findsNothing);
    await container
        .read(personalTopicBarPreferencesProvider.notifier)
        .setOrder(TopicBarAction.values.reversed.toList());
    await tester.pump();
    expect(x(TopicBarAction.bookmark), lessThan(x(TopicBarAction.share)));
    expect(x(TopicBarAction.share), lessThan(x(TopicBarAction.filter)));
    expect(x(TopicBarAction.filter), lessThan(x(TopicBarAction.scrollToTop)));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('拖动设置中的手柄会保存排序，重建后仍保持，重置恢复默认', (tester) async {
    await tester.pumpWidget(host(const PersonalTopicBarSettingsPage()));
    final handle = find.byKey(const ValueKey('topic-bar-drag-bookmark'));
    final top = find.byKey(const ValueKey('topic-bar-order-scrollToTop'));
    final start = tester.getCenter(handle);
    final sourceRect = tester.getRect(
      find.byKey(const ValueKey('topic-bar-order-bookmark')),
    );
    final targetRect = tester.getRect(top);
    // 重排按拖拽代理的上下边缘判定，而不是手指位置。让代理顶部
    // 落在首行上半部中央；原先 center - 20 会让代理底部落在首行
    // 下半部，实际表达的是插入首行之后。
    final grabOffset = start.dy - sourceRect.top;
    final targetY = targetRect.top + targetRect.height / 4 + grabOffset;
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(0, -24));
    await tester.pump();
    await gesture.moveTo(Offset(start.dx, targetY));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(prefs.getStringList(topicBarOrderPreferenceKey), [
      'bookmark',
      'scrollToTop',
      'filter',
      'share',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pumpWidget(host(const PersonalTopicBarSettingsPage()));
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('topic-bar-order-bookmark')))
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('topic-bar-order-scrollToTop')),
            )
            .dy,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('topic-bar-order-reset')));
    await tester.pumpAndSettle();
    expect(
      prefs.getStringList(topicBarOrderPreferenceKey),
      TopicBarAction.values.map((action) => action.name).toList(),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('游客不能调用书签动作，登录后可用且收藏更新立即反映', (tester) async {
    final showBar = ValueNotifier(true);
    final stream = ValueNotifier(1);
    addTearDown(showBar.dispose);
    addTearDown(stream.dispose);
    var calls = 0;
    Widget overlay({required bool loggedIn, required bool bookmarked}) => host(
      Scaffold(
        body: TopicDetailOverlay(
          showBottomBarListenable: showBar,
          isLoggedIn: loggedIn,
          streamIndexListenable: stream,
          totalCount: 1,
          detail: TopicDetail(
            id: 1,
            title: '测试',
            slug: 'test',
            postsCount: 1,
            postStream: PostStream(posts: const [], stream: const [1]),
            categoryId: 1,
            closed: false,
            archived: false,
            bookmarked: bookmarked,
          ),
          isBookmarked: bookmarked,
          onScrollToTop: () {},
          onShare: () {},
          onBookmark: () => calls++,
          onReply: () {},
          onProgressTap: () {},
        ),
      ),
    );
    final bookmark = find.byKey(const ValueKey('topic-bar-bookmark'));
    await tester.pumpWidget(overlay(loggedIn: false, bookmarked: false));
    expect(
      tester
          .widget<IconButton>(
            find.descendant(of: bookmark, matching: find.byType(IconButton)),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(bookmark);
    expect(calls, 0);
    expect(find.byTooltip('请先登录'), findsOneWidget);
    await tester.pumpWidget(overlay(loggedIn: true, bookmarked: false));
    await tester.tap(bookmark);
    expect(calls, 1);
    expect(tester.widget<Icon>(find.byIcon(Symbols.bookmark_rounded)).fill, 0);
    await tester.pumpWidget(overlay(loggedIn: true, bookmarked: true));
    expect(tester.widget<Icon>(find.byIcon(Symbols.bookmark_rounded)).fill, 1);
    expect(find.byTooltip('已收藏'), findsOneWidget);
    await tester.tap(bookmark);
    expect(calls, 2, reason: '已收藏仍可打开现有书签编辑面板');
    await tester.pumpWidget(overlay(loggedIn: true, bookmarked: false));
    expect(tester.widget<Icon>(find.byIcon(Symbols.bookmark_rounded)).fill, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
