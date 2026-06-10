/// AI 包内日志桥接。
///
/// 主应用可注入 [handler] 把包内诊断转到应用日志文件；未注入时为空操作，
/// 保持本地 package 与 app shell 解耦。
typedef AiLogHandler = void Function(String level, String tag, String message);

class AiPackageLogger {
  AiPackageLogger._();

  static AiLogHandler? handler;

  static void info(String tag, String message) {
    handler?.call('info', tag, message);
  }

  static void warning(String tag, String message) {
    handler?.call('warning', tag, message);
  }

  static void error(String tag, String message) {
    handler?.call('error', tag, message);
  }
}
