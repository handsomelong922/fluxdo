import 'package:flutter/foundation.dart';

/// 全局滚动繁忙信号。
///
/// 热路径只更新时间戳，不通知监听器或触发 widget rebuild。后台维护任务和
/// 动图解码可查询 [isBusy]，在用户滚动期间主动让路。
class ScrollBusySignal {
  ScrollBusySignal._();

  @visibleForTesting
  static const Duration busyWindow = Duration(seconds: 1);

  static DateTime _lastScrollAt = DateTime.fromMillisecondsSinceEpoch(0);

  static void touch() => _lastScrollAt = DateTime.now();

  static bool get isBusy =>
      DateTime.now().difference(_lastScrollAt) < busyWindow;

  @visibleForTesting
  static void debugReset({DateTime? lastScrollAt}) {
    _lastScrollAt = lastScrollAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
}
