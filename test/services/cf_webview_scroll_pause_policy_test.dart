import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/cf_webview_scroll_pause_policy.dart';

void main() {
  test('非 Android 平台不改变 WebView 状态', () {
    expect(
      decideCfWebViewScrollPauseAction(
        isAndroid: false,
        isScrollBusy: true,
        isInitialChallengePending: false,
        isCallingRc: false,
        isPausedForScroll: false,
      ),
      CfWebViewScrollPauseAction.none,
    );
  });

  test('首次挑战和 RC 请求期间不允许挂起', () {
    expect(
      decideCfWebViewScrollPauseAction(
        isAndroid: true,
        isScrollBusy: true,
        isInitialChallengePending: true,
        isCallingRc: false,
        isPausedForScroll: false,
      ),
      CfWebViewScrollPauseAction.none,
    );
    expect(
      decideCfWebViewScrollPauseAction(
        isAndroid: true,
        isScrollBusy: true,
        isInitialChallengePending: false,
        isCallingRc: true,
        isPausedForScroll: false,
      ),
      CfWebViewScrollPauseAction.none,
    );
  });

  test('滚动繁忙且安全时只发出一次 pause', () {
    expect(
      decideCfWebViewScrollPauseAction(
        isAndroid: true,
        isScrollBusy: true,
        isInitialChallengePending: false,
        isCallingRc: false,
        isPausedForScroll: false,
      ),
      CfWebViewScrollPauseAction.pause,
    );
    expect(
      decideCfWebViewScrollPauseAction(
        isAndroid: true,
        isScrollBusy: true,
        isInitialChallengePending: false,
        isCallingRc: false,
        isPausedForScroll: true,
      ),
      CfWebViewScrollPauseAction.none,
    );
  });

  test('滚动静默或 RC 开始时恢复已挂起 WebView', () {
    for (final isCallingRc in [false, true]) {
      expect(
        decideCfWebViewScrollPauseAction(
          isAndroid: true,
          isScrollBusy: true,
          isInitialChallengePending: false,
          isCallingRc: isCallingRc,
          isPausedForScroll: true,
        ),
        isCallingRc
            ? CfWebViewScrollPauseAction.resume
            : CfWebViewScrollPauseAction.none,
      );
    }

    expect(
      decideCfWebViewScrollPauseAction(
        isAndroid: true,
        isScrollBusy: false,
        isInitialChallengePending: false,
        isCallingRc: false,
        isPausedForScroll: true,
      ),
      CfWebViewScrollPauseAction.resume,
    );
  });
}
