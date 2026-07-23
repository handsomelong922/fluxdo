import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/app_localizations.dart';
import 'package:fluxdo/models/emoji.dart';
import 'package:fluxdo/providers/emoji_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/utils/emoji_shortcodes.dart';
import 'package:fluxdo/widgets/markdown_editor/emoji_picker.dart';
import 'package:fluxdo/widgets/post/post_boost/boost_input.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<_BoostInputTestHostState> pumpHost(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          emojiGroupsProvider.overrideWith(
            (ref) async => const <String, List<Emoji>>{},
          ),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const _BoostInputTestHost(),
        ),
      ),
    );

    return tester.state<_BoostInputTestHostState>(
      find.byType(_BoostInputTestHost),
    );
  }

  Future<BoostInputResult?> openSheetAndSubmit(
    WidgetTester tester,
    String text,
  ) async {
    final hostState = await pumpHost(tester);
    final resultFuture = hostState.openSheet();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.enterText(find.byType(TextField), text);
    await tester.pump();

    final expectedIcon = visibleLengthWithEmojiShortcodes(text) > 16
        ? Icons.reply_rounded
        : Icons.send_rounded;
    await tester.tap(find.widgetWithIcon(IconButton, expectedIcon));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    return resultFuture;
  }

  testWidgets('16 visible chars submit as boost', (tester) async {
    const text = '1234567890123456';
    expect(visibleLengthWithEmojiShortcodes(text), 16);

    final result = await openSheetAndSubmit(tester, text);

    expect(result, isA<BoostInputBoostResult>());
    expect(result?.raw, text);
  });

  testWidgets('17 visible chars submit as reply', (tester) async {
    const text = '12345678901234567';
    expect(visibleLengthWithEmojiShortcodes(text), 17);

    final result = await openSheetAndSubmit(tester, text);

    expect(result, isA<BoostInputReplyResult>());
    expect(result?.raw, text);
  });

  testWidgets('emoji shortcodes use visible length for submit type', (
    tester,
  ) async {
    const text = ':smile::heart::thumbsup:';

    final result = await openSheetAndSubmit(tester, text);

    expect(result, isA<BoostInputBoostResult>());
    expect(result?.raw, text);
  });

  testWidgets('移动端首次打开 Boost 不挂载 EmojiPicker，点击后再创建', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final hostState = await pumpHost(tester);

      final resultFuture = hostState.openSheet();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(EmojiPicker), findsNothing);
      expect(find.byIcon(Icons.emoji_emotions_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
      await tester.pump();

      expect(find.byType(EmojiPicker), findsOneWidget);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(await resultFuture, isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('桌面端首次打开 Boost 仍默认挂载 EmojiPicker', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final hostState = await pumpHost(tester);

      final resultFuture = hostState.openSheet();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(EmojiPicker), findsOneWidget);
      expect(find.byIcon(Icons.keyboard), findsOneWidget);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(await resultFuture, isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('EmojiPicker 按平台限制屏外预构建范围', () {
    expect(emojiPickerCacheExtentForPlatform(TargetPlatform.android), 160);
    expect(emojiPickerCacheExtentForPlatform(TargetPlatform.iOS), 160);
    expect(emojiPickerCacheExtentForPlatform(TargetPlatform.windows), 480);
    expect(emojiPickerCacheExtentForPlatform(TargetPlatform.macOS), 480);
    expect(emojiPickerCacheExtentForPlatform(TargetPlatform.linux), 480);
  });
}

class _BoostInputTestHost extends StatefulWidget {
  const _BoostInputTestHost();

  @override
  State<_BoostInputTestHost> createState() => _BoostInputTestHostState();
}

class _BoostInputTestHostState extends State<_BoostInputTestHost> {
  Future<BoostInputResult?> openSheet() => showBoostInputSheet(context);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SizedBox.expand());
  }
}
