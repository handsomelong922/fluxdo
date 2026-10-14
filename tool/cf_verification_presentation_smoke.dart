import 'dart:async';

import '../lib/services/cf_verification_presentation.dart';

/// 与 Flutter 测试共用展示策略用例；虚拟计时器不访问网络或验证服务。
final cfVerificationPresentationSmokeTests = <String, void Function()>{
  '自动验证开始时无面板和胶囊，宽限结束只请求一次前台展示': () {
    _withTimers((timers) {
      final presentation = CfVerificationPresentation(
        startInBackground: true,
        quietBackground: true,
      );
      var promotions = 0;
      presentation.startBackgroundDeadline(() {
        promotions++;
        presentation.promote();
      });
      _check(presentation.isBackground, '应先在后台');
      _check(!presentation.showBackgroundIndicator, '不能展示初始胶囊');
      _check(timers.single.duration == const Duration(seconds: 40), '宽限为四十秒');
      timers.single.fire();
      _check(promotions == 1 && !presentation.isBackground, '截止后应请求前台');
      _check(!presentation.promote(), '重复切前台应无效');
    });
  },
  '重复加载不能重置或延长本轮后台宽限': () {
    _withTimers((timers) {
      final presentation = CfVerificationPresentation(startInBackground: true);
      var first = 0;
      var second = 0;
      presentation.startBackgroundDeadline(() => first++);
      presentation.startBackgroundDeadline(() => second++);
      _check(timers.length == 1, '只能创建一次截止计时器');
      timers.single.fire();
      _check(first == 1 && second == 0, '保留最初的截止回调');
      presentation.startBackgroundDeadline(() => second++);
      _check(timers.length == 1, '截止之后也不能重新计时');
      presentation.finish();
    });
  },
  '手动前台入口不延迟；原有后台入口仍可显示胶囊': () {
    _withTimers((timers) {
      final manual = CfVerificationPresentation(startInBackground: false);
      manual.startBackgroundDeadline(() => throw StateError('前台不应有截止回调'));
      _check(!manual.isBackground && timers.isEmpty, '手动入口立即前台');
      _check(!manual.showBackgroundIndicator, '前台无胶囊');
      final background = CfVerificationPresentation(startInBackground: true);
      _check(background.showBackgroundIndicator, '保留普通后台入口的胶囊');
      manual.finish();
      background.finish();
    });
  },
  '提前完成、销毁或手动提升均取消截止，迟到回调不再打断': () {
    for (final action in ['finish', 'dispose', 'promote']) {
      _withTimers((timers) {
        final presentation = CfVerificationPresentation(
          startInBackground: true,
        );
        var promotions = 0;
        presentation.startBackgroundDeadline(() => promotions++);
        switch (action) {
          case 'finish':
            presentation.finish();
          case 'dispose':
            presentation.dispose();
          case 'promote':
            _check(presentation.promote(), '首次手动提升有效');
        }
        _check(!timers.single.isActive, '$action 必须取消计时器');
        timers.single.fireEvenIfCancelled();
        _check(promotions == 0, '$action 后迟到回调不能展示前台');
        presentation.startBackgroundDeadline(() => promotions++);
        _check(timers.length == 1, '$action 后不能再启动计时器');
        if (action != 'promote') {
          _check(!presentation.promote(), '结束后不能提升前台');
        }
      });
    }
  },
};

void main() {
  for (final test in cfVerificationPresentationSmokeTests.entries) {
    test.value();
    print('通过：${test.key}');
  }
  print('展示策略 ${cfVerificationPresentationSmokeTests.length} 项全部通过');
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _withTimers(void Function(List<_ControlledTimer>) body) {
  final timers = <_ControlledTimer>[];
  runZoned(
    () => body(timers),
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        final timer = _ControlledTimer(duration, callback);
        timers.add(timer);
        return timer;
      },
    ),
  );
}

class _ControlledTimer implements Timer {
  _ControlledTimer(this.duration, this.callback);

  final Duration duration;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    callback();
  }

  void fireEvenIfCancelled() => callback();

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}
