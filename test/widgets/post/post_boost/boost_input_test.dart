import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/app_localizations.dart';
import 'package:fluxdo/models/emoji.dart';
import 'package:fluxdo/providers/emoji_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/utils/emoji_shortcodes.dart';
import 'package:fluxdo/widgets/post/post_boost/boost_input.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<BoostInputResult?> openSheetAndSubmit(
    WidgetTester tester,
    String text,
  ) async {
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

    final hostState = tester.state<_BoostInputTestHostState>(
      find.byType(_BoostInputTestHost),
    );
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
