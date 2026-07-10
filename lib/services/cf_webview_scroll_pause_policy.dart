enum CfWebViewScrollPauseAction { none, pause, resume }

CfWebViewScrollPauseAction decideCfWebViewScrollPauseAction({
  required bool isAndroid,
  required bool isScrollBusy,
  required bool isInitialChallengePending,
  required bool isCallingRc,
  required bool isPausedForScroll,
}) {
  if (!isAndroid) return CfWebViewScrollPauseAction.none;

  final shouldPause =
      isScrollBusy && !isInitialChallengePending && !isCallingRc;
  if (shouldPause == isPausedForScroll) {
    return CfWebViewScrollPauseAction.none;
  }
  return shouldPause
      ? CfWebViewScrollPauseAction.pause
      : CfWebViewScrollPauseAction.resume;
}
