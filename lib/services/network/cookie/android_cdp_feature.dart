import 'dart:io' show Platform;

import 'package:shared_preferences/shared_preferences.dart';

import '../../app_logger.dart';

class AndroidCdpFeature {
  AndroidCdpFeature._();

  static const String prefKey = 'pref_android_native_cdp';
  static bool _enabled = true;
  static bool _initialized = false;

  static bool get isEnabled => Platform.isAndroid && _enabled;

  static Future<void> initialize(SharedPreferences prefs) async {
    _enabled = prefs.getBool(prefKey) ?? true;
    _initialized = true;
    AppLogger.info(
      'Android native CDP ${_enabled ? 'enabled' : 'disabled'}',
      tag: 'AndroidCdp',
    );
  }

  static Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKey, enabled);
    AppLogger.warning(
      'Android native CDP switched ${enabled ? 'on' : 'off'}',
      tag: 'AndroidCdp',
    );
  }

  static bool get isInitialized => _initialized;
}
