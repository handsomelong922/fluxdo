import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/scroll_busy_signal.dart';

void main() {
  tearDown(ScrollBusySignal.debugReset);

  test('touch 后进入滚动繁忙窗口', () {
    ScrollBusySignal.debugReset();
    expect(ScrollBusySignal.isBusy, isFalse);

    ScrollBusySignal.touch();
    expect(ScrollBusySignal.isBusy, isTrue);
  });

  test('超过静默窗口后自动恢复空闲', () {
    ScrollBusySignal.debugReset(
      lastScrollAt: DateTime.now().subtract(
        ScrollBusySignal.busyWindow + const Duration(milliseconds: 1),
      ),
    );

    expect(ScrollBusySignal.isBusy, isFalse);
  });
}
