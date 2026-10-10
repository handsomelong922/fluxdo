import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/models/topic_card_style.dart';
import 'package:fluxdo/pages/topic_card_style_settings_page.dart';
import 'package:fluxdo/providers/preferences_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/settings/widgets/topic_title_color_dialog.dart';
import 'package:fluxdo/widgets/topic/painted_topic_card.dart';
import 'package:fluxdo/widgets/topic/topic_card.dart';
import 'package:fluxdo/widgets/topic/topic_card_layout.dart';
import 'package:fluxdo/widgets/topic/topic_item_builder.dart';
import 'package:shared_preferences/shared_preferences.dart';

Topic _topic({bool read = false, bool pinned = false, bool rich = false}) =>
    Topic(
      id: 1,
      title: 'Title color test',
      slug: 'color-test',
      postsCount: 2,
      replyCount: 1,
      views: 20,
      likeCount: 0,
      categoryId: '1',
      unseen: !read,
      lastReadPostNumber: read ? 2 : null,
      pinned: pinned,
      closed: rich,
    );

Future<ProviderContainer> _container(TopicCardStyle style) async {
  SharedPreferences.setMockInitialValues({
    'pref_topic_card_style': style.toJsonString(),
  });
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

Widget _app(ProviderContainer container, Widget child, ThemeData theme) =>
    UncontrolledProviderScope(
      container: container,
      child: TranslationProvider(
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: theme,
          home: Scaffold(body: child),
        ),
      ),
    );

Future<void> _expectParagraphColor(
  WidgetTester tester,
  ui.Paragraph paragraph,
  Color expected,
) async {
  final bytes = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.drawParagraph(paragraph, Offset.zero);
    final picture = recorder.endRecording();
    final image = await picture.toImage(400, 100);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    return data!;
  });
  final rgb = Color.alphaBlend(expected, Colors.white).toARGB32();
  var matched = 0;
  for (var i = 0; i < bytes!.lengthInBytes; i += 4) {
    if ((bytes.getUint8(i) - ((rgb >> 16) & 255)).abs() <= 1 &&
        (bytes.getUint8(i + 1) - ((rgb >> 8) & 255)).abs() <= 1 &&
        (bytes.getUint8(i + 2) - (rgb & 255)).abs() <= 1)
      matched++;
  }
  expect(matched, greaterThan(0));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    TopicCardLayout.evictAll();
    TopicCardStyleScope.current = TopicCardStyle.defaults;
  });

  test('颜色持久化、重载、单独重置保留字号，旧值和畸形颜色安全回退', () async {
    const style = TopicCardStyle(titleFontSize: 17, titleColor: 0xFF336699);
    expect(TopicCardStyle.fromJsonString(style.toJsonString()), style);
    expect(style, isNot(TopicCardStyle.defaults));
    expect(style.copyWith(titleColor: 0xFF112233), isNot(style));
    expect(
      TopicCardStyle.fromJsonString('{"titleFontSize":17}').titleColor,
      isNull,
    );
    for (final raw in [
      'null',
      '"red"',
      '-1',
      '4294967296',
      '0',
      '2164260863',
      '1.5',
    ]) {
      final parsed = TopicCardStyle.fromJsonString(
        '{"titleFontSize":17,"titleColor":$raw}',
      );
      expect(parsed.titleColor, isNull);
      expect(parsed.titleFontSize, 17);
    }
    final container = await _container(TopicCardStyle.defaults);
    addTearDown(container.dispose);
    await container.read(preferencesProvider.notifier).setTopicCardStyle(style);
    final prefs = container.read(sharedPreferencesProvider);
    final reloaded = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(reloaded.dispose);
    expect(reloaded.read(preferencesProvider).topicCardStyle, style);
    await reloaded
        .read(preferencesProvider.notifier)
        .setTopicCardStyle(style.copyWith(resetTitleColor: true));
    final saved = TopicCardStyle.fromJsonString(
      prefs.getString('pref_topic_card_style'),
    );
    expect(saved.titleColor, isNull);
    expect(saved.titleFontSize, 17);
    expect(TopicCardStyleScope.current, saved);
  });

  for (final brightness in Brightness.values) {
    for (final read in [false, true]) {
      for (final custom in [false, true]) {
        testWidgets('普通/置顶组件 $brightness 已读=$read 自定义=$custom', (tester) async {
          final style = TopicCardStyle(
            titleFontSize: 17,
            titleColor: custom ? 0xFF336699 : null,
          );
          final container = await _container(style);
          addTearDown(container.dispose);
          final theme = ThemeData(brightness: brightness);
          for (final pinned in [false, true]) {
            for (final rich in [false, true]) {
              final topic = _topic(read: read, pinned: pinned, rich: rich);
              final card = pinned
                  ? CompactTopicCard(topic: topic, categoryMap: const {})
                  : TopicCard(
                      topic: topic,
                      categoryMap: const {},
                      hideAvatar: true,
                    );
              await tester.pumpWidget(_app(container, card, theme));
              final title = tester.widget<Text>(
                find
                    .byWidgetPredicate(
                      (widget) =>
                          widget is Text &&
                          (widget.data == topic.title ||
                              (widget.textSpan?.toPlainText().contains(
                                    topic.title,
                                  ) ??
                                  false)),
                    )
                    .first,
              );
              final textStyle =
                  title.style ?? (title.textSpan! as TextSpan).style!;
              final expected = custom
                  ? const Color(0xFF336699)
                  : read
                  ? (pinned
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.75,
                          ))
                  : theme.colorScheme.onSurface;
              expect(textStyle.color, expected);
              if (!pinned && !rich) {
                final layout = TopicCardLayout.obtain(
                  identity: 'matrix-title',
                  topic: topic,
                  width: 360,
                  theme: theme,
                  category: null,
                  emojiUrlOf: (_) => '',
                  style: style,
                );
                await _expectParagraphColor(tester, layout.title!, expected);
              }
              expect(
                textStyle.fontSize,
                pinned ? theme.textTheme.labelMedium!.fontSize : 17,
              );
              expect(
                textStyle.fontWeight,
                pinned
                    ? (read ? FontWeight.w400 : FontWeight.w500)
                    : (read ? FontWeight.w500 : FontWeight.w600),
              );
              expect(tester.takeException(), isNull);
            }
          }
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  testWidgets('首页自绘实际标题采用新颜色，修改与重置使缓存失效', (tester) async {
    final container = await _container(TopicCardStyle.defaults);
    addTearDown(container.dispose);
    final topic = _topic();
    final theme = ThemeData.dark();
    Future<TopicCardLayout> pump() async {
      await tester.pumpWidget(
        _app(
          container,
          Consumer(
            builder: (context, ref, _) {
              ref.watch(preferencesProvider.select((p) => p.topicCardStyle));
              return buildTopicItem(
                context: context,
                topic: topic,
                isSelected: false,
                onTap: () {},
                enableLongPress: false,
                hideAvatar: true,
                categoryMap: const {},
              );
            },
          ),
          theme,
        ),
      );
      return tester
          .widget<PaintedTopicCard>(find.byType(PaintedTopicCard))
          .layout;
    }

    final initial = await pump();
    await container
        .read(preferencesProvider.notifier)
        .setTopicCardStyle(const TopicCardStyle(titleColor: 0xFF336699));
    final custom = await pump();
    expect(identical(custom, initial), isFalse);
    // 检查实际自绘段落的像素，而非只验证设置值或源码字符串。
    final bytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawParagraph(custom.title!, Offset.zero);
      final picture = recorder.endRecording();
      final image = await picture.toImage(400, 100);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      picture.dispose();
      return data!;
    });
    var matched = 0;
    for (var i = 0; i < bytes!.lengthInBytes; i += 4) {
      if (bytes.getUint8(i) == 0x33 &&
          bytes.getUint8(i + 1) == 0x66 &&
          bytes.getUint8(i + 2) == 0x99 &&
          bytes.getUint8(i + 3) == 255)
        matched++;
    }
    expect(matched, greaterThan(0));
    await container
        .read(preferencesProvider.notifier)
        .setTopicCardStyle(TopicCardStyle.defaults);
    final reset = await pump();
    expect(identical(reset, custom), isFalse);
    expect(reset.title!.height, initial.title!.height);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('私信组件与自绘不受自定义颜色影响', (tester) async {
    final container = await _container(
      const TopicCardStyle(titleColor: 0xFF336699),
    );
    addTearDown(container.dispose);
    final theme = ThemeData.dark();
    final topic = _topic();
    await tester.pumpWidget(
      _app(
        container,
        TopicCard(topic: topic, messageStyle: true, categoryMap: const {}),
        theme,
      ),
    );
    final title = tester.widget<Text>(find.text(topic.title));
    expect(
      title.style!.color,
      theme.colorScheme.onSurface.withValues(alpha: 0.9),
    );
    TopicCardLayout layout(TopicCardStyle style) => TopicCardLayout.obtain(
      identity: 'private-color',
      topic: topic,
      width: 360,
      theme: theme,
      category: null,
      emojiUrlOf: (_) => '',
      messageStyle: true,
      style: style,
    );
    expect(
      identical(
        layout(TopicCardStyle.defaults),
        layout(const TopicCardStyle(titleColor: 0xFF336699)),
      ),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('窄屏深色取色器提示低对比度，取消不保存', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = await _container(TopicCardStyle.defaults);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      _app(
        container,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<int>(
              context: context,
              builder: (_) =>
                  const TopicTitleColorDialog(initialColor: 0xFF121212),
            ),
            child: const Text('open'),
          ),
        ),
        ThemeData.dark(),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l10n = tester.element(find.byType(TopicTitleColorDialog)).l10n;
    expect(
      find.text(l10n.topicCardStyle_titleColorLowContrast),
      findsOneWidget,
    );
    await tester.tap(find.text(l10n.common_cancel));
    await tester.pumpAndSettle();
    expect(find.byType(TopicTitleColorDialog), findsNothing);
    expect(
      container.read(preferencesProvider).topicCardStyle.titleColor,
      isNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('颜色设置色板、HEX 校验、保存和单独重置', (tester) async {
    final container = await _container(const TopicCardStyle(titleFontSize: 17));
    addTearDown(container.dispose);
    await tester.pumpWidget(
      _app(container, const TopicCardStyleSettingsPage(), ThemeData()),
    );
    final context = tester.element(find.byType(TopicCardStyleSettingsPage));
    final l10n = context.l10n;
    await tester.ensureVisible(find.text(l10n.topicCardStyle_titleColor));
    await tester.tap(find.text(l10n.topicCardStyle_titleColor));
    await tester.pumpAndSettle();
    expect(find.byType(TopicTitleColorDialog), findsOneWidget);
    await tester.tap(find.byTooltip('#1565C0'));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '1565C0',
    );
    await tester.enterText(find.byType(TextField), 'oops');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, l10n.common_save),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), '#336699');
    await tester.pump();
    await tester.tap(find.text(l10n.common_save));
    await tester.pumpAndSettle();
    expect(
      container.read(preferencesProvider).topicCardStyle.titleColor,
      0xFF336699,
    );
    final tile = find.ancestor(
      of: find.text(l10n.topicCardStyle_titleColor),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: tile, matching: find.text(l10n.common_reset)),
    );
    await tester.pump();
    expect(
      container.read(preferencesProvider).topicCardStyle.titleColor,
      isNull,
    );
    expect(
      container.read(preferencesProvider).topicCardStyle.titleFontSize,
      17,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
