import 'dart:async';

/// 每个进程只做一次普通读取预热。UI 不等待本任务；失败不改变页面状态。
/// 依赖通过回调传入，避免测试需要真实网络、WebView 或验证挑战。
class StartupConnectionWarmup {
  Future<void>? _active;
  bool _cancelled = false;

  Future<void> start({
    required bool Function() canRun,
    required Future<void> Function() prepare,
    required Future<bool?> Function() joinVerification,
    required Future<void> Function() probe,
  }) {
    return _active ??= Future<void>.microtask(() async {
      bool allowed() => !_cancelled && canRun();
      if (!allowed()) return;
      try {
        await prepare();
        if (!allowed()) return;
        // 已有验证无论成功或失败，都不由预热另开一轮。null 表示无任务。
        final joined = await joinVerification();
        if (!allowed() || joined != null) return;
        await probe();
      } catch (_) {
        // 断网、超时、取消或验证失败留给下一次用户读取正常处理。
      }
    });
  }

  void cancel() => _cancelled = true;
}
