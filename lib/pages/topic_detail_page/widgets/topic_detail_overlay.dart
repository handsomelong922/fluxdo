import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../models/topic.dart';
import '../../../widgets/topic/topic_progress.dart';
import 'progress_gesture_action_meta.dart';
import 'topic_bottom_bar.dart';
import 'topic_progress_gestures.dart';

const topicDetailBarAnimationDuration = Duration(milliseconds: 200);
const topicDetailBarAnimationCurve = Curves.easeOutCubic;

/// 话题详情页浮层
/// 包含进度栏、底部操作栏和悬浮回复按钮
class TopicDetailOverlay extends StatelessWidget {
  final bool showBottomBar;
  final bool isLoggedIn;
  final ValueListenable<int> currentStreamIndexListenable;
  final int totalCount;
  final TopicDetail detail;
  final VoidCallback onScrollToTop;
  final VoidCallback onShare;
  final VoidCallback? onShareAsImage;
  final VoidCallback? onExport;
  final VoidCallback onBookmark;
  final VoidCallback onBookmarkLongPress;
  final VoidCallback onReply;
  final VoidCallback onProgressTap;
  final ValueChanged<ProgressGestureAction>? onProgressAction;
  final bool showProgress;
  final bool isSummaryMode;
  final bool isAuthorOnlyMode;
  final bool isTopLevelMode;
  final bool isLoading;
  final VoidCallback? onShowTopReplies;
  final VoidCallback? onShowAuthorOnly;
  final VoidCallback? onShowTopLevelReplies;
  final VoidCallback? onCancelFilter;

  const TopicDetailOverlay({
    super.key,
    required this.showBottomBar,
    required this.isLoggedIn,
    required this.currentStreamIndexListenable,
    required this.totalCount,
    required this.detail,
    required this.onScrollToTop,
    required this.onShare,
    this.onShareAsImage,
    this.onExport,
    required this.onBookmark,
    required this.onBookmarkLongPress,
    required this.onReply,
    required this.onProgressTap,
    this.onProgressAction,
    this.showProgress = true,
    this.isSummaryMode = false,
    this.isAuthorOnlyMode = false,
    this.isTopLevelMode = false,
    this.isLoading = false,
    this.onShowTopReplies,
    this.onShowAuthorOnly,
    this.onShowTopLevelReplies,
    this.onCancelFilter,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const progressVisibleBottom = 96.0;
    final progressHiddenBottom = 24.0 + bottomPadding;
    final progressHiddenOffsetY = progressVisibleBottom - progressHiddenBottom;

    const bottomBarVisibleBottom = 8.0;
    const bottomBarHiddenBottom = -88.0;
    const bottomBarHiddenOffsetY =
        bottomBarVisibleBottom - bottomBarHiddenBottom;

    final fabVisibleBottom = bottomPadding + (80 - bottomPadding - 56) / 2;
    final fabHiddenBottom = 16.0 + bottomPadding;
    final fabHiddenOffsetY = fabVisibleBottom - fabHiddenBottom;

    return Stack(
      children: [
        // 固定的进度栏
        if (showProgress)
          Positioned(
            key: const ValueKey('progress_bar'),
            bottom: progressVisibleBottom,
            left: 0,
            right: 0,
            child: _PaintOffsetTransition(
              offsetY: showBottomBar ? 0 : progressHiddenOffsetY,
              child: ValueListenableBuilder<int>(
                valueListenable: currentStreamIndexListenable,
                builder: (context, currentStreamIndex, _) {
                  final progressPercent = totalCount > 1
                      ? (currentStreamIndex - 1) / (totalCount - 1)
                      : 0.0;
                  return Center(
                    child: TopicProgressGestures(
                      onAction: (action) {
                        if (action == ProgressGestureAction.openTimeline) {
                          onProgressTap();
                        } else {
                          onProgressAction?.call(action);
                        }
                      },
                      child: TopicProgress(
                        currentIndex: currentStreamIndex,
                        totalCount: totalCount,
                        progressPercent: progressPercent,
                        onTap: onProgressTap,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        // 底部操作栏
        Positioned(
          key: const ValueKey('bottom_bar'),
          left: 16,
          right: 16,
          bottom: bottomBarVisibleBottom,
          child: IgnorePointer(
            ignoring: !showBottomBar,
            child: _PaintOffsetTransition(
              offsetY: showBottomBar ? 0 : bottomBarHiddenOffsetY,
              child: AnimatedOpacity(
                opacity: showBottomBar ? 1 : 0,
                duration: topicDetailBarAnimationDuration,
                curve: topicDetailBarAnimationCurve,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: TopicBottomBar(
                      onScrollToTop: onScrollToTop,
                      onShare: onShare,
                      onShareAsImage: onShareAsImage,
                      onExport: onExport,
                      onBookmark: onBookmark,
                      onBookmarkLongPress: onBookmarkLongPress,
                      hasSummary: detail.hasSummary,
                      isBookmarked: detail.bookmarked,
                      isSummaryMode: isSummaryMode,
                      isAuthorOnlyMode: isAuthorOnlyMode,
                      isTopLevelMode: isTopLevelMode,
                      isLoading: isLoading,
                      isPrivateMessage: detail.isPrivateMessage,
                      onShowTopReplies: onShowTopReplies,
                      onShowAuthorOnly: onShowAuthorOnly,
                      onShowTopLevelReplies: onShowTopLevelReplies,
                      onCancelFilter: onCancelFilter,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // 悬浮回复按钮
        if (isLoggedIn)
          Positioned(
            key: const ValueKey('fab_reply'),
            right: 16,
            bottom: fabVisibleBottom,
            child: _PaintOffsetTransition(
              offsetY: showBottomBar ? 0 : fabHiddenOffsetY,
              child: FloatingActionButton(
                heroTag: 'replyTopic',
                onPressed: onReply,
                child: const Icon(Icons.reply),
              ),
            ),
          ),
      ],
    );
  }
}

class _PaintOffsetTransition extends StatelessWidget {
  const _PaintOffsetTransition({required this.offsetY, required this.child});

  final double offsetY;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: offsetY),
      duration: topicDetailBarAnimationDuration,
      curve: topicDetailBarAnimationCurve,
      builder: (context, value, child) {
        return Transform.translate(offset: Offset(0, value), child: child);
      },
      child: child,
    );
  }
}
