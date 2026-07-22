import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/app_localizations.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/home_topic_excerpt_provider.dart';
import 'package:fluxdo/providers/preferences_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/providers/topic_detail_provider.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/services/topic_detail_cache_service.dart';
import 'package:fluxdo/widgets/topic/topic_preview_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('短正文预览在最低与最高高度之间自适应并分隔元信息', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final loader = HomeTopicExcerptLoader(
      fetchPreview: (topicId) async => _previewDetail(topicId),
    );
    addTearDown(loader.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          categoryMapProvider.overrideWithValue(const AsyncValue.data({})),
          homeTopicExcerptLoaderProvider.overrideWithValue(loader),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: TopicPreviewDialog(topic: _topicWithManyTags())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final window = find.byKey(TopicPreviewDialog.previewWindowKey);
    expect(window, findsOneWidget);
    final windowHeight = tester.getSize(window).height;
    expect(
      windowHeight,
      greaterThanOrEqualTo(844 * TopicPreviewDialog.minViewportHeightFactor),
    );
    expect(
      windowHeight,
      lessThan(844 * TopicPreviewDialog.viewportHeightFactor),
    );
    expect(find.byType(AnimatedSize), findsOneWidget);
    expect(
      tester.widget<AnimatedSize>(find.byType(AnimatedSize)).duration,
      TopicPreviewDialog.resizeDuration,
    );
    expect(find.byKey(TopicPreviewDialog.metadataDividerKey), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).gradient != null,
      ),
      findsNothing,
    );
    expect(find.text('查看详情'), findsOneWidget);
    expect(find.text('关闭'), findsNothing);
    expect(find.byIcon(Icons.share_outlined), findsNothing);
    expect(find.text('参与者'), findsNothing);

    final replyText = tester.widget<Text>(find.text('7'));
    final viewsText = tester.widget<Text>(find.text('321'));
    final replyIcon = tester.widget<Icon>(
      find.byIcon(Icons.chat_bubble_outline_rounded),
    );
    final viewsIcon = tester.widget<Icon>(
      find.byIcon(Icons.visibility_outlined),
    );
    expect(replyText.style?.fontSize, greaterThan(viewsText.style!.fontSize!));
    expect(replyText.style?.fontWeight, FontWeight.w700);
    expect(replyIcon.size, greaterThan(viewsIcon.size!));
    expect(tester.takeException(), isNull);
  });

  testWidgets('长正文预览不超过现有最高高度', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final longHtml = List.generate(
      80,
      (index) => '<p>这是用于验证最大高度限制的正文第 $index 行。</p>',
    ).join();
    final loader = HomeTopicExcerptLoader(
      fetchPreview: (topicId) async =>
          _previewDetail(topicId, cooked: longHtml),
    );
    addTearDown(loader.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          categoryMapProvider.overrideWithValue(const AsyncValue.data({})),
          homeTopicExcerptLoaderProvider.overrideWithValue(loader),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: TopicPreviewDialog(topic: _topicWithManyTags())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(TopicPreviewDialog.previewWindowKey)).height,
      lessThanOrEqualTo(844 * TopicPreviewDialog.viewportHeightFactor),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('查看详情前把已展示的首帖写入 preview seed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final loader = HomeTopicExcerptLoader(
      fetchPreview: (topicId) async => _previewDetail(topicId),
    );
    final cache = TopicDetailCacheService();
    var openCount = 0;
    addTearDown(loader.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          categoryMapProvider.overrideWithValue(const AsyncValue.data({})),
          homeTopicExcerptLoaderProvider.overrideWithValue(loader),
          topicDetailCacheServiceProvider.overrideWithValue(cache),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => TopicPreviewDialog.show(
                  context,
                  topic: _topicWithManyTags(),
                  trigger: TopicPreviewTrigger.rightSideTap,
                  onOpen: () => openCount++,
                ),
                child: const Text('打开预览'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开预览'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();

    final seeded = cache.read(42);
    expect(openCount, 1);
    expect(seeded?.isPreviewSeed, isTrue);
    expect(
      seeded?.detail.postStream.posts.single.cooked,
      contains('final value = 1;'),
    );
    expect(cache.shouldRevalidate(seeded!), isTrue);
  });
}

Topic _topicWithManyTags() {
  final now = DateTime(2026, 7, 14, 12);
  return Topic(
    id: 42,
    title: '固定高度预览测试',
    slug: 'preview-test',
    postsCount: 8,
    replyCount: 7,
    views: 321,
    likeCount: 12,
    createdAt: now,
    lastPostedAt: now,
    lastPosterUsername: 'tester',
    categoryId: '1',
    tags: List.generate(12, (index) => Tag(id: index, name: '很长的标签$index')),
  );
}

TopicDetail _previewDetail(
  int topicId, {
  String cooked = '<p>正文</p><pre><code>final value = 1;</code></pre>',
}) {
  final now = DateTime(2026, 7, 14, 12);
  return TopicDetail(
    id: topicId,
    title: '固定高度预览测试',
    slug: 'preview-test',
    postsCount: 8,
    postStream: PostStream(
      posts: [
        Post(
          id: 42001,
          topicId: topicId,
          username: 'tester',
          avatarTemplate: '',
          cooked: cooked,
          postNumber: 1,
          postType: 1,
          updatedAt: now,
          createdAt: now,
          likeCount: 12,
          replyCount: 0,
        ),
      ],
      stream: const [42001],
    ),
    categoryId: 1,
    closed: false,
    archived: false,
    views: 321,
    likeCount: 12,
    createdAt: now,
  );
}
