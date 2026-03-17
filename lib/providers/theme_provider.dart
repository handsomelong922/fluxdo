import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 内置字体选项
enum AppFontFamily {
  /// 跟随系统默认字体
  system,
  /// 内置 MiSans 字体
  miSans,
}

/// App Theme State
class ThemeState {
  final ThemeMode mode;
  final Color seedColor;
  final bool useDynamicColor;
  final AppFontFamily fontFamily;

  const ThemeState({
    required this.mode,
    required this.seedColor,
    this.useDynamicColor = false,
    this.fontFamily = AppFontFamily.system,
  });

  /// 获取实际用于 ThemeData 的 fontFamily 字符串
  String? get fontFamilyName {
    switch (fontFamily) {
      case AppFontFamily.miSans:
        return 'MiSans';
      case AppFontFamily.system:
        return null;
    }
  }

  ThemeState copyWith({
    ThemeMode? mode,
    Color? seedColor,
    bool? useDynamicColor,
    AppFontFamily? fontFamily,
  }) {
    return ThemeState(
      mode: mode ?? this.mode,
      seedColor: seedColor ?? this.seedColor,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}

/// App Theme Notifier
class ThemeNotifier extends StateNotifier<ThemeState> {
  static const String _themeModeKey = 'theme_mode';
  static const String _seedColorKey = 'seed_color';
  static const String _dynamicColorKey = 'use_dynamic_color';
  static const String _fontFamilyKey = 'font_family';
  final SharedPreferences _prefs;

  // Preset Colors
  static const List<Color> presetColors = [
    Colors.blue,
    Colors.purple,
    Colors.green,
    Colors.orange,
    Colors.pink,
    Colors.teal,
    Colors.red,
    Colors.indigo,
    Colors.amber,
    Colors.cyan,
  ];

  ThemeNotifier(this._prefs) : super(_loadTheme(_prefs));

  static ThemeState _loadTheme(SharedPreferences prefs) {
    // Load Mode
    final savedMode = prefs.getString(_themeModeKey);
    ThemeMode mode = ThemeMode.system;
    if (savedMode == 'light') {
      mode = ThemeMode.light;
    } else if (savedMode == 'dark') {
      mode = ThemeMode.dark;
    }

    // Load Color
    final savedColorValue = prefs.getInt(_seedColorKey);
    Color seedColor = Colors.blue;
    if (savedColorValue != null) {
      seedColor = Color(savedColorValue);
    }

    // Load Dynamic Color
    final useDynamicColor = prefs.getBool(_dynamicColorKey) ?? false;

    // Load Font Family
    final savedFontFamily = prefs.getString(_fontFamilyKey);
    AppFontFamily fontFamily = AppFontFamily.system;
    if (savedFontFamily == 'miSans') {
      fontFamily = AppFontFamily.miSans;
    }

    return ThemeState(
      mode: mode,
      seedColor: seedColor,
      useDynamicColor: useDynamicColor,
      fontFamily: fontFamily,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
    String value = 'system';
    if (mode == ThemeMode.light) {
      value = 'light';
    } else if (mode == ThemeMode.dark) {
      value = 'dark';
    }
    await _prefs.setString(_themeModeKey, value);
  }

  Future<void> setSeedColor(Color color) async {
    state = state.copyWith(seedColor: color, useDynamicColor: false);
    await _prefs.setInt(_seedColorKey, color.toARGB32());
    await _prefs.setBool(_dynamicColorKey, false);
  }

  Future<void> setUseDynamicColor(bool value) async {
    state = state.copyWith(useDynamicColor: value);
    await _prefs.setBool(_dynamicColorKey, value);
  }

  Future<void> setFontFamily(AppFontFamily fontFamily) async {
    state = state.copyWith(fontFamily: fontFamily);
    switch (fontFamily) {
      case AppFontFamily.system:
        await _prefs.setString(_fontFamilyKey, 'system');
      case AppFontFamily.miSans:
        await _prefs.setString(_fontFamilyKey, 'miSans');
    }
  }
}

/// SharedPreferences Provider
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

/// Theme Provider
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeNotifier(prefs);
});
