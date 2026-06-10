/// 请求调度器的全局配置
///
/// 用户可通过「网络设置 → 限流设置」调整。
/// [RequestSchedulerInterceptor] 在每次请求时动态读取这些值。
class RequestSchedulerConfig {
  RequestSchedulerConfig._();

  /// 最大并发请求数（默认 3）
  static int maxConcurrent = 3;

  /// 滑动窗口内最大请求数（默认 6）
  static int maxPerWindow = 6;

  /// 滑动窗口时长，单位秒（默认 3）
  static int windowSeconds = 3;

  static DateTime? _serverCooldownUntil;

  /// 服务端返回 429 后暂停新请求，避免自动刷新继续把限流窗口顶满。
  static void pauseFor(Duration duration) {
    if (duration <= Duration.zero) return;
    final until = DateTime.now().add(duration);
    if (_serverCooldownUntil == null || until.isAfter(_serverCooldownUntil!)) {
      _serverCooldownUntil = until;
    }
  }

  static Duration get serverCooldownRemaining {
    final until = _serverCooldownUntil;
    if (until == null) return Duration.zero;
    final remaining = until.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _serverCooldownUntil = null;
      return Duration.zero;
    }
    return remaining;
  }

  static void resetServerCooldownForTesting() {
    _serverCooldownUntil = null;
  }
}
