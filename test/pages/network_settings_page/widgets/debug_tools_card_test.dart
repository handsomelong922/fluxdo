import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/app_localizations.dart';
import 'package:fluxdo/pages/network_settings_page/widgets/debug_tools_card.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'developer tools are present on the first frame without async growth',
    (tester) async {
      SharedPreferences.setMockInitialValues({'developer_mode': true});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(child: DebugToolsCard()),
            ),
          ),
        ),
      );

      expect(find.text('CF 验证状态'), findsOneWidget);
      await tester.pump();
      expect(find.text('CF 验证状态'), findsOneWidget);
    },
  );
}
