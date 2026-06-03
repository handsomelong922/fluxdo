import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'session_cookie_sentinel.dart';

/// 监听 WebView cookie store 的外部变化，并触发 sweep。
///
/// macOS/iOS 由 native `WKHTTPCookieStoreObserver` 推送变化；
/// Android 主要由 WebView `onLoadStop` 主动通知。Windows/Linux 暂无等价
/// observer，也走主动通知兜底。
class CookieStoreObserver {
  CookieStoreObserver._();
  static final CookieStoreObserver instance = CookieStoreObserver._();

  static const _channel = MethodChannel('com.fluxdo/cookie_observer');
  static const Duration _debounceWindow = Duration(milliseconds: 500);

  bool _attached = false;
  Timer? _debounce;
  final Set<String> _knownUrls = {};

  bool get hasNativeObserver => io.Platform.isMacOS || io.Platform.isIOS;

  /// 启动监听，重复调用安全。
  void attach() {
    if (_attached) return;
    _attached = true;
    if (hasNativeObserver) {
      _channel.setMethodCallHandler(_handleNativeCall);
    }
    debugPrint(
      '[CookieObserver] attached on ${io.Platform.operatingSystem} '
      '(nativeObserver=$hasNativeObserver)',
    );
  }

  /// Dart 端主动触发一次外部 cookie 变化检查。
  void notifyExternalChange() {
    _onCookiesChanged();
  }

  /// 注册后续需要 sweep 的 url。
  void registerUrl(String url) {
    if (url.isEmpty) return;
    _knownUrls.add(url);
  }

  @visibleForTesting
  void resetForTest() {
    _debounce?.cancel();
    _debounce = null;
    _knownUrls.clear();
    _attached = false;
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onCookiesChanged') {
      _onCookiesChanged();
    }
    return null;
  }

  void _onCookiesChanged() {
    _debounce?.cancel();
    _debounce = Timer(_debounceWindow, _doSweep);
  }

  Future<void> _doSweep() async {
    final urls = _knownUrls.toList(growable: false);
    if (urls.isEmpty) return;
    debugPrint(
      '[CookieObserver] external cookie change detected, sweepAll for $urls',
    );
    for (final url in urls) {
      try {
        final results = await SessionCookieSentinel.instance.sweepAll(url);
        final mismatch = results
            .where(
              (r) => r.variantsBefore != r.variantsAfter || r.variantsAfter > 1,
            )
            .toList();
        if (mismatch.isNotEmpty) {
          debugPrint(
            '[CookieObserver] sweepAll($url) handled '
            '${mismatch.length} cookies: $mismatch',
          );
        }
      } catch (e) {
        debugPrint('[CookieObserver] sweepAll($url) failed: $e');
      }
    }
  }
}
