import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_provider.dart';

/// null 表示跟随系统语言
class LocaleNotifier extends StateNotifier<Locale?> {
  static const String _localeKey = 'pref_locale';
  final SharedPreferences _prefs;

  LocaleNotifier(this._prefs) : super(_loadLocale(_prefs));

  static Locale? _loadLocale(SharedPreferences prefs) {
    final saved = prefs.getString(_localeKey);
    if (saved == null || saved == 'system') return null;
    final parts = saved.split('_');
    return switch (parts.first) {
      'zh' => const Locale('zh'),
      'en' => const Locale('en'),
      _ => null,
    };
  }

  Future<void> setLocale(Locale? locale) async {
    state = locale;
    if (locale == null) {
      await _prefs.setString(_localeKey, 'system');
    } else {
      await _prefs.setString(_localeKey, locale.languageCode);
    }
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return LocaleNotifier(prefs);
});
