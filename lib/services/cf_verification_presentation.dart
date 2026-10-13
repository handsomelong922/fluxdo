import 'dart:async';

/// 只管理验证界面的展示时机，不参与挑战执行、Cookie 或通过判定。
///
/// 后台宽限从页面创建开始，只计时一次；导航、页面就绪及站点自身重试
/// 都不能延长它。即使主文档一直没有就绪，也会把原验证界面交给用户。
class CfVerificationPresentation {
  CfVerificationPresentation({
    required bool startInBackground,
    this.quietBackground = false,
  }) : _isBackground = startInBackground;

  static const backgroundGracePeriod = Duration(seconds: 10);

  final bool quietBackground;
  bool _isBackground;
  bool _finished = false;
  bool _deadlineStarted = false;
  Timer? _backgroundDeadline;

  bool get isBackground => _isBackground;
  bool get showBackgroundIndicator =>
      !_finished && _isBackground && !quietBackground;

  void startBackgroundDeadline(void Function() onDeadline) {
    if (_finished || !_isBackground || _deadlineStarted) return;
    _deadlineStarted = true;
    _backgroundDeadline = Timer(backgroundGracePeriod, () {
      _backgroundDeadline = null;
      if (!_finished && _isBackground) onDeadline();
    });
  }

  /// 返回是否真的从后台切到前台，合并重复的提升请求。
  bool promote() {
    if (_finished || !_isBackground) return false;
    _backgroundDeadline?.cancel();
    _backgroundDeadline = null;
    _isBackground = false;
    return true;
  }

  void finish() {
    _finished = true;
    _backgroundDeadline?.cancel();
    _backgroundDeadline = null;
  }

  void dispose() => finish();
}
