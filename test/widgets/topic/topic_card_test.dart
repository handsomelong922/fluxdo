import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/app_localizations.dart';
import 'package:fluxdo/models/category.dart';
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

  testWidgets('移动端 TopicCard 使用轻量外壳并保留摘要与交互', (tester) async {
    await _setSurfaceSize(tester, const Size(390, 844));
    var tapCount = 0;
    var longPressCount = 0;
    const cardColor = Color(0xFF223344);
    const summaryKey = ValueKey('home-excerpt');

    await _pumpCard(
      tester,
      theme: ThemeData(
        useMaterial3: true,
        cardTheme: const CardThemeData(elevation: 0, color: cardColor),
      ),
      child: TopicCard(
        topic: _topic(),
        onTap: () => tapCount++,
        onLongPress: () => longPressCount++,
        bottomWidget: const Text('主帖摘要内容', key: summaryKey),
      ),
    );

    final cardScope = find.byType(TopicCard);
    expect(
      find.descendant(of: cardScope, matching: find.byType(Card)),
      findsNothing,
    );
    expect(find.byKey(summaryKey), findsOneWidget);
    expect(_findSurfaceDecoration(color: cardColor), findsOneWidget);
    expect(_findBottomPadding(8), findsOneWidget);

    await tester.tap(find.text('测试话题'));
    await tester.pump();
    expect(tapCount, 1);

    await tester.longPress(find.text('测试话题'));
    await tester.pump();
    expect(longPressCount, 1);
  });

  testWidgets('移动端选中 TopicCard 保留颜色与描边', (tester) async {
    await _setSurfaceSize(tester, const Size(390, 844));
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
    );

    await _pumpCard(
      tester,
      theme: theme,
      child: TopicCard(topic: _topic(), isSelected: true),
    );

    final expectedColor = theme.colorScheme.primaryContainer.withValues(
      alpha: 0.4,
    );
    final expectedBorderColor = theme.colorScheme.primary.withValues(
      alpha: 0.5,
    );
    expect(
      _findSurfaceDecoration(
        color: expectedColor,
        borderColor: expectedBorderColor,
      ),
      findsOneWidget,
    );
  });

  testWidgets('TopicCard 右侧全高热区只触发预览且不触发详情', (tester) async {
    await _setSurfaceSize(tester, const Size(390, 844));
    var tapCount = 0;
    var previewCount = 0;

    await _pumpCard(
      tester,
      child: TopicCard(
        topic: _topic(),
        onTap: () => tapCount++,
        onPreviewTap: () => previewCount++,
        bottomWidget: const Text('跨越卡片宽度的摘要正文'),
      ),
    );

    final zone = find.byKey(TopicCard.previewTapZoneKey);
    expect(zone, findsOneWidget);
    final zoneRect = tester.getRect(zone);
    final cardRect = tester.getRect(find.byType(TopicCard));
    expect(zoneRect.top, cardRect.top);
    expect(zoneRect.bottom, cardRect.bottom - 8);

    await tester.tapAt(zoneRect.center);
    await tester.pump();
    expect(previewCount, 1);
    expect(tapCount, 0);

    await tester.tap(find.text('测试话题'));
    await tester.pump();
    expect(previewCount, 1);
    expect(tapCount, 1);
  });

  testWidgets('CompactTopicCard 复用右侧全高预览热区', (tester) async {
    await _setSurfaceSize(tester, const Size(390, 844));
    var tapCount = 0;
    var previewCount = 0;

    await _pumpCard(
      tester,
      child: CompactTopicCard(
        topic: _topic(pinned: true),
        onTap: () => tapCount++,
        onPreviewTap: () => previewCount++,
      ),
    );

    final zone = find.byKey(TopicCard.previewTapZoneKey);
    await tester.tap(zone);
    await tester.pump();
    expect(previewCount, 1);
    expect(tapCount, 0);
  });

  testWidgets('移动端 CompactTopicCard 使用轻量外壳', (tester) async {
    await _setSurfaceSize(tester, const Size(390, 844));
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
    );

    await _pumpCard(
      tester,
      theme: theme,
      child: CompactTopicCard(topic: _topic(pinned: true)),
    );

    final cardScope = find.byType(CompactTopicCard);
    expect(
      find.descendant(of: cardScope, matching: find.byType(Card)),
      findsNothing,
    );
    expect(
      _findSurfaceDecoration(
        color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
      ),
      findsOneWidget,
    );
    expect(_findBottomPadding(6), findsOneWidget);
  });

  testWidgets('非移动端 TopicCard 与 CompactTopicCard 继续使用 Card', (tester) async {
    await _setSurfaceSize(tester, const Size(900, 800));

    await _pumpCard(
      tester,
      child: Column(
        children: [
          TopicCard(topic: _topic()),
          CompactTopicCard(topic: _topic(pinned: true)),
        ],
      ),
    );

    expect(find.byType(Card), findsNWidgets(2));
  });

  testWidgets('TopicCard 优先使用列表传入的分类快照', (tester) async {
    final category = Category(
      id: 1,
      name: '列表快照分类',
      color: '336699',
      textColor: 'FFFFFF',
      slug: 'snapshot',
    );

    await _pumpCard(
      tester,
      child: Column(
        children: [
          TopicCard(topic: _topic(), categoryMap: {1: category}),
          CompactTopicCard(
            topic: _topic(pinned: true),
            categoryMap: {1: category},
          ),
        ],
      ),
    );

    expect(find.text('列表快照分类'), findsOneWidget);
  });
}

Future<void> _setSurfaceSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required Widget child,
  ThemeData? theme,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        categoryMapProvider.overrideWithValue(const AsyncValue.data({})),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

Finder _findSurfaceDecoration({required Color color, Color? borderColor}) {
  return find.byWidgetPredicate((widget) {
    if (widget is! DecoratedBox) return false;
    final decoration = widget.decoration;
    if (decoration is! ShapeDecoration || decoration.color != color) {
      return false;
    }
    final shape = decoration.shape;
    if (shape is! RoundedRectangleBorder ||
        shape.borderRadius != BorderRadius.circular(10)) {
      return false;
    }
    if (borderColor == null) return shape.side == BorderSide.none;
    return shape.side.color == borderColor && shape.side.width == 1;
  });
}

Finder _findBottomPadding(double bottom) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Padding && widget.padding == EdgeInsets.only(bottom: bottom),
  );
}

Topic _topic({bool pinned = false}) {
  final now = DateTime(2026, 7, 12, 12);
  return Topic(
    id: pinned ? 2 : 1,
    title: '测试话题',
    slug: 'test-topic',
    postsCount: 2,
    replyCount: 1,
    views: 10,
    likeCount: 1,
    createdAt: now,
    lastPostedAt: now,
    lastPosterUsername: 'tester',
    categoryId: '1',
    pinned: pinned,
  );
}
