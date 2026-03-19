import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 统一管理 Windows 平台的 WebView2 Environment。
///
/// 目标：
/// 1. 固定 userDataFolder，避免默认落在 exe 同级目录。
/// 2. 让 CookieManager / InAppWebView / HeadlessInAppWebView 使用同一环境。
class WindowsWebViewEnvironmentService {
  WindowsWebViewEnvironmentService._internal();

  static final WindowsWebViewEnvironmentService instance =
      WindowsWebViewEnvironmentService._internal();

  WebViewEnvironment? _environment;
  CookieManager? _cookieManager;
  Future<void>? _initializeFuture;
  String? _userDataFolder;

  bool get _isSupported => !kIsWeb && Platform.isWindows;

  WebViewEnvironment? get environment => _environment;

  String? get userDataFolder => _userDataFolder;

  CookieManager get cookieManager {
    if (_isSupported && _environment != null) {
      return _cookieManager ??=
          CookieManager.instance(webViewEnvironment: _environment);
    }
    return CookieManager.instance();
  }

  Future<void> initialize() {
    if (!_isSupported || _environment != null) {
      return Future.value();
    }
    return _initializeFuture ??= _initializeInternal();
  }

  Future<void> _initializeInternal() async {
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final userDataFolder = path.join(supportDirectory.path, 'webview2');
      final userDataDirectory = Directory(userDataFolder);
      if (!await userDataDirectory.exists()) {
        await userDataDirectory.create(recursive: true);
      }

      _environment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(userDataFolder: userDataFolder),
      );
      _userDataFolder = userDataFolder;
      _cookieManager = CookieManager.instance(webViewEnvironment: _environment);

      debugPrint(
        '[WebViewEnv] Windows WebView2 environment initialized: '
        'userDataFolder=$userDataFolder',
      );
    } catch (e, stackTrace) {
      debugPrint('[WebViewEnv] Windows environment init failed: $e');
      debugPrintStack(
        label: '[WebViewEnv] initialize stack',
        stackTrace: stackTrace,
      );
      _initializeFuture = null;
    }
  }
}
