import 'dart:async';

/// 页面可以先关闭，但业务请求必须等本轮快照同步和原生析构全部完成。
/// 清理异常或失去响应时返回 false，调用方仍需释放该轮的流量冻结。
Future<bool> waitForCfVerificationCleanup({
  required bool verificationPassed,
  required Future<void> teardown,
  Future<void>? cookieSync,
  Duration timeout = const Duration(minutes: 2),
}) async {
  try {
    await Future.wait<void>([teardown, if (cookieSync != null) cookieSync])
        .timeout(timeout);
    return verificationPassed;
  } catch (_) {
    return false;
  }
}
