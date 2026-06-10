import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Eruda 设备内 DevTools 开关。
///
/// Eruda 打包在 compat polyfill bundle 中，默认关闭。关闭时
/// WebViewSettings 会在 polyfill 前注入 guard，阻止 eruda-init 初始化。
class ErudaSettingsService {
  ErudaSettingsService._internal();

  static final ErudaSettingsService instance = ErudaSettingsService._internal();

  static const _enabledKey = 'eruda_enabled';

  final ValueNotifier<bool> notifier = ValueNotifier(false);

  SharedPreferences? _prefs;

  bool get enabled => notifier.value;

  Future<void> initialize(SharedPreferences prefs) async {
    if (_prefs != null) return;
    _prefs = prefs;
    notifier.value = prefs.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = _prefs;
    if (prefs == null) return;
    notifier.value = value;
    await prefs.setBool(_enabledKey, value);
  }
}
