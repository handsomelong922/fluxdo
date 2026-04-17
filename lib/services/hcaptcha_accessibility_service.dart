import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'windows_webview_environment_service.dart';

/// hCaptcha 无障碍 Cookie 管理服务
///
/// 支持视障用户通过无障碍 Cookie 跳过 hCaptcha 验证。
/// Cookie 会在打开登录页时自动同步到 WebView。
/// 仅在 Android 和 Windows 平台可用（Apple 平台 WKWebView
/// 从底层阻止跨域 iframe 中的第三方 Cookie 访问）。
class HCaptchaAccessibilityService {
  static final HCaptchaAccessibilityService _instance =
      HCaptchaAccessibilityService._internal();
  factory HCaptchaAccessibilityService() => _instance;
  HCaptchaAccessibilityService._internal();

  static const _keyEnabled = 'hcaptcha_accessibility_enabled';
  static const _keyCookie = 'hcaptcha_accessibility_cookie';
  static const cookieName = 'hc_accessibility';

  late SharedPreferences _prefs;

  final enabledNotifier = ValueNotifier<bool>(false);
  final cookieNotifier = ValueNotifier<String?>(null);

  bool get enabled => enabledNotifier.value;
  String? get cookie => cookieNotifier.value;

  void initialize(SharedPreferences prefs) {
    _prefs = prefs;
    enabledNotifier.value = prefs.getBool(_keyEnabled) ?? false;
    cookieNotifier.value = prefs.getString(_keyCookie);
  }

  Future<void> setEnabled(bool value) async {
    enabledNotifier.value = value;
    await _prefs.setBool(_keyEnabled, value);
  }

  Future<void> setCookie(String value) async {
    cookieNotifier.value = value;
    await _prefs.setString(_keyCookie, value);
  }

  Future<void> clearCookie() async {
    cookieNotifier.value = null;
    await _prefs.remove(_keyCookie);
  }

  /// 将无障碍 Cookie 同步到 WebView 的 hcaptcha.com 域
  Future<void> syncToWebView() async {
    if (!enabled || cookie == null || cookie!.isEmpty) return;

    try {
      final cookieManager =
          WindowsWebViewEnvironmentService.instance.cookieManager;
      await cookieManager.setCookie(
        url: WebUri('https://www.hcaptcha.com'),
        name: cookieName,
        value: cookie!,
        domain: '.hcaptcha.com',
        path: '/',
        isSecure: true,
        sameSite: HTTPCookieSameSitePolicy.NONE,
      );
      debugPrint('[hCaptcha] Cookie synced to WebView');
    } catch (e) {
      debugPrint('[hCaptcha] Failed to sync cookie: $e');
    }
  }
}
