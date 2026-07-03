import 'package:flutter/foundation.dart';

/// 运行时诊断日志开关。
///
/// 默认面向正式浏览体验：仅保留必要错误/警告日志，避免高频诊断日志持续写盘。
/// 调试输出和详细持久化日志分开控制：
/// - Debug 构建保留控制台调试输出
/// - Developer Mode 才开启详细持久化日志
class RuntimeLogSettings {
  RuntimeLogSettings._();

  static bool _developerModeEnabled = false;

  static void configure({required bool developerModeEnabled}) {
    _developerModeEnabled = developerModeEnabled;
  }

  static bool get developerModeEnabled => _developerModeEnabled;

  static bool get emitVerboseConsoleDiagnostics =>
      kDebugMode || _developerModeEnabled;

  static bool get persistVerboseDiagnostics => _developerModeEnabled;

  static bool shouldPersistDiagnosticEvent({required String level}) {
    if (persistVerboseDiagnostics) return true;
    return level == 'warning' || level == 'error';
  }

  static bool shouldPersistRequestLog({
    required String level,
    required bool isSilent,
  }) {
    if (persistVerboseDiagnostics) return true;
    if (level == 'warning' || level == 'error') return true;
    return !isSilent;
  }
}
