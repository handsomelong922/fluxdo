import 'package:flutter/foundation.dart';

import 'log/log_writer.dart';
import 'toast_service.dart';

/// 全局错误处理器
class AppErrorHandler {
  AppErrorHandler._();

  /// 处理非网络层的意外异常
  ///
  /// DioException 由 ErrorInterceptor 统一处理（toast + 拦截），
  /// 此方法用于捕获其余程序异常（解析错误、类型转换、未知响应格式等），
  /// 显示通用 toast 并写入本地日志。
  static void handleUnexpected(Object error, StackTrace stackTrace) {
    debugPrint('[AppErrorHandler] 意外异常: $error\n$stackTrace');
    ToastService.showError('操作失败，请重试');
    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'error',
      'type': 'unexpected',
      'error': error.toString(),
      'errorType': error.runtimeType.toString(),
      'stackTrace': stackTrace.toString(),
    });
  }
}
