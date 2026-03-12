import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_dynamic_icon_plus/flutter_dynamic_icon_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_provider.dart';

/// 应用图标风格（用户只选择风格，深浅色由系统自适应处理）
enum AppIconStyle {
  /// 经典 FluxDO 图标
  classic,

  /// 现代图标
  modern,
}

/// 应用图标状态
class AppIconState {
  final AppIconStyle currentStyle;
  final bool isChanging;

  const AppIconState({
    this.currentStyle = AppIconStyle.classic,
    this.isChanging = false,
  });

  AppIconState copyWith({
    AppIconStyle? currentStyle,
    bool? isChanging,
  }) {
    return AppIconState(
      currentStyle: currentStyle ?? this.currentStyle,
      isChanging: isChanging ?? this.isChanging,
    );
  }
}

/// 应用图标管理
class AppIconNotifier extends StateNotifier<AppIconState> {
  static const String _prefKey = 'pref_app_icon';
  static const _androidChannel =
      MethodChannel('com.github.lingyan000.fluxdo/app_icon');
  final SharedPreferences _prefs;

  AppIconNotifier(this._prefs) : super(const AppIconState()) {
    _init();
  }

  void _init() {
    // 兼容旧值：'default'/'default_dark' → classic，'modern'/'modern_light' → modern
    final saved = _prefs.getString(_prefKey);
    final AppIconStyle style;
    switch (saved) {
      case 'modern':
      case 'modern_light':
        style = AppIconStyle.modern;
      default:
        style = AppIconStyle.classic;
    }

    state = state.copyWith(currentStyle: style);
  }

  /// 根据风格获取平台图标名（深浅色由系统自适应处理）
  String? _getIconName(AppIconStyle style) {
    switch (style) {
      case AppIconStyle.classic:
        return null; // null = 主图标
      case AppIconStyle.modern:
        return 'ModernIcon';
    }
  }

  /// 调用平台 API 切换图标
  Future<void> _setPlatformIcon(String? iconName) async {
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      await _androidChannel
          .invokeMethod('setAlternateIcon', {'iconName': iconName});
    } else if (Platform.isIOS) {
      await FlutterDynamicIconPlus.setAlternateIconName(iconName: iconName);
    }
  }

  /// 切换应用图标风格
  Future<bool> setIconStyle(AppIconStyle style) async {
    if (state.isChanging || style == state.currentStyle) return true;

    state = state.copyWith(isChanging: true);

    try {
      final iconName = _getIconName(style);
      await _setPlatformIcon(iconName);
      await _prefs.setString(
        _prefKey,
        style == AppIconStyle.modern ? 'modern' : 'classic',
      );

      state = state.copyWith(
        currentStyle: style,
        isChanging: false,
      );
      return true;
    } catch (e) {
      debugPrint('切换应用图标失败: $e');
      state = state.copyWith(isChanging: false);
      return false;
    }
  }
}

/// 应用图标 Provider
final appIconProvider =
    StateNotifierProvider<AppIconNotifier, AppIconState>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AppIconNotifier(prefs);
});
