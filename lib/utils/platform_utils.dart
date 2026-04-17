import 'dart:io';

import 'package:flutter/foundation.dart';

/// 平台工具类 — 统一平台检测逻辑
class PlatformUtils {
  PlatformUtils._();

  /// 是否运行在桌面操作系统（macOS / Windows / Linux）
  static bool get isDesktop =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// 是否运行在移动操作系统（Android / iOS）
  static bool get isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);
}
