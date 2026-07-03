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
  static bool _appLogsEnabled = true;
  static int _appLogEntryLimit = 150;

  static void configure({
    bool? developerModeEnabled,
    bool? appLogsEnabled,
    int? appLogEntryLimit,
  }) {
    if (developerModeEnabled != null) {
      _developerModeEnabled = developerModeEnabled;
    }
    if (appLogsEnabled != null) {
      _appLogsEnabled = appLogsEnabled;
    }
    if (appLogEntryLimit != null) {
      _appLogEntryLimit = appLogEntryLimit.clamp(50, 300).toInt();
    }
  }

  static bool get developerModeEnabled => _developerModeEnabled;
  static bool get appLogsEnabled => _appLogsEnabled;
  static int get appLogEntryLimit => _appLogEntryLimit;

  static bool get emitVerboseConsoleDiagnostics =>
      kDebugMode || _developerModeEnabled;

  static bool get persistVerboseDiagnostics => _developerModeEnabled;

  static bool shouldPersistDiagnosticEvent({required String level}) {
    if (!_appLogsEnabled) return false;
    if (persistVerboseDiagnostics) return true;
    return level == 'warning' || level == 'error';
  }

  static bool shouldPersistRequestLog({
    required String level,
    required bool isSilent,
  }) {
    if (!_appLogsEnabled) return false;
    if (persistVerboseDiagnostics) return true;
    if (level == 'warning' || level == 'error') return true;
    return !isSilent;
  }
}
