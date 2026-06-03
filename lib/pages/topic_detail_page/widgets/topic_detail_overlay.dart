import 'package:flutter/material.dart';
import '../../../models/topic.dart';
import '../../../widgets/topic/topic_progress.dart';
import 'topic_bottom_bar.dart';

const topicDetailBarAnimationDuration = Duration(milliseconds: 200);
const topicDetailBarAnimationCurve = Curves.linear;

/// 话题详情页浮层
/// 包含进度栏、底部操作栏和悬浮回复按钮
class TopicDetailOverlay extends StatelessWidget {
  final bool showBottomBar;
  final bool isLoggedIn;
  final int currentStreamIndex;
  final int totalCount;
  final TopicDetail detail;
  final VoidCallback onScrollToTop;
  final VoidCallback onShare;
  final VoidCallback? onShareAsImage;
  final VoidCallback? onExport;
  final VoidCallback onBookmark;
  final VoidCallback onReply;
  final VoidCallback onProgressTap;
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
    required this.currentStreamIndex,
    required this.totalCount,
    required this.detail,
    required this.onScrollToTop,
    required this.onShare,
    this.onShareAsImage,
    this.onExport,
    required this.onBookmark,
    required this.onReply,
    required this.onProgressTap,
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
    final progressPercent = totalCount > 1
        ? (currentStreamIndex - 1) / (totalCount - 1)
        : 0.0;

    return Stack(
      children: [
        // 固定的进度栏
        if (showProgress)
          AnimatedPositioned(
            key: const ValueKey('progress_bar'),
            duration: topicDetailBarAnimationDuration,
            curve: topicDetailBarAnimationCurve,
            bottom: showBottomBar ? 96 : 24 + bottomPadding,
            left: 0,
            right: 0,
            child: Center(
              child: TopicProgress(
                currentIndex: currentStreamIndex,
                totalCount: totalCount,
                progressPercent: progressPercent,
                onTap: onProgressTap,
              ),
            ),
          ),
        // 底部操作栏
        AnimatedPositioned(
          key: const ValueKey('bottom_bar'),
          duration: topicDetailBarAnimationDuration,
          curve: topicDetailBarAnimationCurve,
          left: 16,
          right: 16,
          bottom: showBottomBar ? 8 : -88,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: TopicBottomBar(
                onScrollToTop: onScrollToTop,
                onShare: onShare,
                onShareAsImage: onShareAsImage,
                onExport: onExport,
                onBookmark: onBookmark,
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
        // 悬浮回复按钮
        if (isLoggedIn)
          AnimatedPositioned(
            key: const ValueKey('fab_reply'),
            duration: topicDetailBarAnimationDuration,
            curve: topicDetailBarAnimationCurve,
            right: 16,
            bottom: showBottomBar
                ? bottomPadding + (80 - bottomPadding - 56) / 2
                : 16 + bottomPadding,
            child: FloatingActionButton(
              heroTag: 'replyTopic',
              onPressed: onReply,
              child: const Icon(Icons.reply),
            ),
          ),
      ],
    );
  }
}
