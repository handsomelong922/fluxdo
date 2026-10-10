import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/models/topic_card_style.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/discourse_cache_manager.dart';
import 'package:fluxdo/widgets/common/animated_avatar_overlay.dart';
import 'package:fluxdo/widgets/topic/painted_topic_card.dart';
import 'package:fluxdo/widgets/topic/topic_card.dart';
import 'package:fluxdo/widgets/topic/topic_card_layout.dart';
import 'package:fluxdo/widgets/topic/topic_item_builder.dart';
import 'package:shared_preferences/shared_preferences.dart';

Topic _topic({bool withPoster = true}) => Topic(
  id: 1,
  title: '测试话题',
  slug: 'avatar-test',
  postsCount: 2,
  replyCount: 1,
  views: 20,
  likeCount: 2,
  categoryId: '1',
  lastPosterUsername: '测试作者',
  posters: withPoster
      ? [
          TopicPoster(
            userId: 1,
            description: 'Original Poster',
            extras: '',
            user: TopicUser(
              id: 1,
              username: '测试作者',
              avatarTemplate: 'https://example.com/avatar/{size}.png',
              animatedAvatar: 'https://example.com/avatar.gif',
            ),
          ),
        ]
      : [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(TopicCardLayout.evictAll);
  tearDown(() {
    TopicCardLayout.evictAll();
    TopicCardStyleScope.current = TopicCardStyle.defaults;
  });

  for (final avatarLayout in TopicCardAvatarLayout.values) {
    test('隐藏 $avatarLayout 头像后移除图片与左侧占位，关闭后恢复', () {
      final topic = _topic();
      final theme = ThemeData();
      final style = TopicCardStyle(avatarLayout: avatarLayout);
      TopicCardLayout layout(bool hidden) => TopicCardLayout.obtain(
        identity: 'avatar-layout',
        topic: topic,
        width: 360,
        theme: theme,
        category: null,
        emojiUrlOf: (_) => '',
        style: style,
        hideAvatar: hidden,
      );
      final visible = layout(false);
      expect(visible.avatarRect.isEmpty, isFalse);
      expect(visible.avatarUrl, isNotNull);
      expect(visible.animatedAvatarUrl, isNotNull);
      final hidden = layout(true);
      expect(identical(visible, hidden), isFalse);
      expect(hidden.avatarRect, Rect.zero);
      expect(hidden.avatarUrl, isNull);
      expect(hidden.animatedAvatarUrl, isNull);
      expect(hidden.titleOffset.dx, 12);
      expect(hidden.authorOffset.dx, 12);
      expect(hidden.cardHeight, lessThanOrEqualTo(visible.cardHeight));
      expect(identical(hidden, layout(true)), isTrue);
      hidden.ensureWidth(500);
      expect(hidden.avatarRect, Rect.zero);
      expect(hidden.authorOffset.dx, 12);
      final restored = layout(false);
      expect(restored.avatarRect, visible.avatarRect);
      expect(restored.authorOffset.dx, visible.authorOffset.dx);
    });
  }

  test('未指定隐藏参数及私信卡均保留头像', () {
    final topic = _topic();
    for (final messageStyle in [false, true]) {
      final layout = TopicCardLayout.obtain(
        identity: 'default-$messageStyle',
        topic: topic,
        width: 360,
        theme: ThemeData(),
        category: null,
        emojiUrlOf: (_) => '',
        messageStyle: messageStyle,
        hideAvatar: messageStyle,
      );
      expect(layout.avatarRect.isEmpty, isFalse);
      expect(layout.avatarUrl, isNotNull);
    }
  });

  testWidgets('首页自绘调用隐藏静态与动态头像，点击保持有效', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var tapped = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => buildTopicItem(
                context: context,
                topic: _topic(),
                isSelected: false,
                onTap: () => tapped = true,
                enableLongPress: false,
                hideAvatar: true,
              ),
            ),
          ),
        ),
      ),
    );
    final card = tester.widget<PaintedTopicCard>(find.byType(PaintedTopicCard));
    expect(card.layout.avatarRect, Rect.zero);
    expect(card.layout.avatarUrl, isNull);
    expect(find.byType(AnimatedAvatarOverlay), findsNothing);
    await tester.tap(find.byType(PaintedTopicCard));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('动态头像隐藏再显示时恢复静态兜底，等待新 overlay 就绪', (tester) async {
    const url = 'https://example.com/animated-avatar.png';
    final provider = discourseImageProvider(url);
    final image = await tester.runAsync(() => createTestImage(cache: false));
    PaintingBinding.instance.imageCache.putIfAbsent(
      provider,
      () => OneFrameImageStreamCompleter(Future.value(ImageInfo(image: image!))),
    );
    addTearDown(() => PaintingBinding.instance.imageCache.evict(provider));
    final topic = _topic(withPoster: false);
    final theme = ThemeData();
    TopicCardLayout layout(bool hidden) => TopicCardLayout.obtain(
      identity: 'animated-toggle',
      topic: topic,
      width: 360,
      theme: theme,
      category: null,
      emojiUrlOf: (_) => '',
      hideAvatar: hidden,
    );
    final visible = layout(false)..animatedAvatarUrl = url;
    final hidden = layout(true);
    Future<void> pump(TopicCardLayout value) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 360, child: PaintedTopicCard(layout: value)),
        ),
      ),
    );
    await pump(visible);
    await tester.pump();
    expect(find.byType(AnimatedAvatarOverlay), findsOneWidget);
    expect(
      find.byType(PaintedTopicCard),
      paintsExactlyCountTimes(#drawOval, 0),
    );
    await pump(hidden);
    expect(find.byType(AnimatedAvatarOverlay), findsNothing);
    // 清除已加载的图像，让新 overlay 等待下一张图片，不访问网络。
    PaintingBinding.instance.imageCache.evict(provider);
    PaintingBinding.instance.imageCache.putIfAbsent(
      provider,
      () => OneFrameImageStreamCompleter(Completer<ImageInfo>().future),
    );
    await pump(visible);
    expect(find.byType(AnimatedAvatarOverlay), findsOneWidget);
    expect(
      find.byType(PaintedTopicCard),
      paintsExactlyCountTimes(#drawOval, 1),
    );
    expect(tester.takeException(), isNull);
  });

  for (final avatarLayout in TopicCardAvatarLayout.values) {
    testWidgets('Widget 回退路径也移除 $avatarLayout 头像和空隙', (tester) async {
      SharedPreferences.setMockInitialValues({
        'pref_topic_card_style': TopicCardStyle(avatarLayout: avatarLayout)
            .toJsonString(),
      });
      final prefs = await SharedPreferences.getInstance();
      Future<void> pump(bool hideAvatar) => tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: TranslationProvider(
            child: MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 360,
                  child: TopicCard(
                    topic: _topic(withPoster: false),
                    categoryMap: const {},
                    hideAvatar: hideAvatar,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await pump(false);
      expect(find.byType(CircleAvatar), findsOneWidget);
      final visibleX = tester.getTopLeft(find.text('测试作者')).dx;
      await pump(true);
      expect(find.byType(CircleAvatar), findsNothing);
      final hiddenX = tester.getTopLeft(find.text('测试作者')).dx;
      expect(hiddenX, 12);
      expect(hiddenX, lessThan(visibleX));
      await pump(false);
      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(tester.getTopLeft(find.text('测试作者')).dx, visibleX);
      expect(tester.takeException(), isNull);
    });
  }
}
