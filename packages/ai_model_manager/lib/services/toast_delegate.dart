/// 消息提示类型
enum AiToastType { success, error, info }

/// 消息提示代理
///
/// 由主项目注入具体实现，包内统一调用
class AiToastDelegate {
  static void Function(String message, {AiToastType type})? _showToast;

  /// 注入消息提示实现
  static void configure(
      void Function(String message, {AiToastType type}) showToast) {
    _showToast = showToast;
  }

  static void showSuccess(String message) {
    _showToast?.call(message, type: AiToastType.success);
  }

  static void showError(String message) {
    _showToast?.call(message, type: AiToastType.error);
  }

  static void showInfo(String message) {
    _showToast?.call(message, type: AiToastType.info);
  }
}
