import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/locale_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('LocaleNotifier', () {
    test(
      'maps old traditional Chinese preferences to simplified Chinese',
      () async {
        SharedPreferences.setMockInitialValues({'pref_locale': 'zh_TW'});
        final prefs = await SharedPreferences.getInstance();

        final notifier = LocaleNotifier(prefs);

        expect(notifier.state, const Locale('zh'));
      },
    );

    test('persists only language code for supported locales', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = LocaleNotifier(prefs);

      await notifier.setLocale(const Locale('zh'));
      expect(prefs.getString('pref_locale'), 'zh');

      await notifier.setLocale(const Locale('en'));
      expect(prefs.getString('pref_locale'), 'en');
    });
  });
}
