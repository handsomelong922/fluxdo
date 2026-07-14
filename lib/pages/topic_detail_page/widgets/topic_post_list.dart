import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show ValueNotifier, setEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/scheduler.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../../l10n/s.dart';
import '../../../models/topic.dart';
import '../../../pages/search_page.dart';
import '../../../providers/message_bus_providers.dart';
import '../../../services/toast_service.dart';
import '../../../services/performance_diagnostics_service.dart';
import '../../../utils/blocked_user_filter.dart';
import '../../../utils/code_selection_context.dart';
import '../../../utils/responsive.dart';
import '../../../utils/time_utils.dart';
import '../../../widgets/content/lazy_load_scope.dart';
import '../../../widgets/content/discourse_html_content/chunked/chunked_html_content.dart';
import '../../../widgets/content/discourse_html_content/chunked/html_chunk.dart';
import '../../../widgets/content/discourse_html_content/chunked/html_chunk_cache.dart';
import '../../../widgets/content/discourse_html_content/image_utils.dart';
import '../../../widgets/post/post_item/post_item.dart';
import '../../../widgets/post/post_item/quote_selection_helper.dart';
import '../../../widgets/post/post_item/segmented_long_post.dart';
import '../../../widgets/post/post_item/widgets/post_footer_section/post_footer_section.dart';
import 'topic_linear_loading_indicator.dart';
import 'topic_detail_header.dart';
import 'topic_post_materialization.dart';
import 'typing_indicator.dart';

@visibleForTesting
String topicPostRenderIdentityKey({
  required int topicId,
  required int postNumber,
  required String segmentType,
  int? chunkIndex,
}) {
  final base = '$segmentType-$topicId-$postNumber';
  return chunkIndex == null ? base : '$base-$chunkIndex';
}

/// 话题帖子列表
/// 负责构建 CustomScrollView 及其 Slivers
///
/// Before-center 和 after-center 帖子使用 SliverList.builder 实现虚拟化：
/// Flutter 会在 item 离开 viewport + cacheExtent 范围时自动 dispose 对应 widget，
/// 释放视频播放器、WebView 等资源。
/// 长帖子内部的 HTML 分块由 ChunkedHtmlContent 的 Column + SelectionArea 处理，
/// 保留跨块文本选择能力。
class TopicPostList extends StatefulWidget {
  final TopicDetail detail;
  final Set<String> blockedUsernames;
  final AutoScrollController scrollController;
  final GlobalKey centerKey;
  final GlobalKey headerKey;
  final double topContentInset;
  final double topBoundaryHeight;
  final int? highlightPostNumber;
  final bool isLoggedIn;
  final bool hasMoreBefore;
  final bool hasMoreAfter;
  final bool isLoadingPrevious;
  final bool isLoadingMore;
  final int incomingUnloadedPostCount;
  final bool isLoadMoreFailed;
  final bool isLoadPreviousFailed;
  final VoidCallback? onRetryLoadMore;
  final VoidCallback? onRetryLoadPrevious;
  final VoidCallback? onLoadIncomingReplies;
  final int centerPostIndex;
  final int? dividerPostIndex;
  final void Function(int postNumber) onFirstVisiblePostChanged;
  final void Function(Set<int> visiblePostNumbers)? onVisiblePostsChanged;
  final void Function(Map<int, int>)? onScrollIndexMappingChanged;
  final void Function(int postNumber) onJumpToPost;
  final void Function(Post? replyToPost) onReply;
  final void Function(Post? replyToPost, String initialContent)?
  onReplyWithInitialContent;
  final void Function(Post post) onEdit;
  final void Function(Post post)? onShareAsImage;
  final void Function(int postId) onRefreshPost;
  final void Function(int, bool) onVoteChanged;
  final void Function(int, bool) onSharedIssueChanged;
  final void Function(TopicNotificationLevel)? onNotificationLevelChanged;
  final void Function(int postId, bool accepted)? onSolutionChanged;
  final void Function(TopicSummary summary)? onContinueAiSummary;
  final void Function(String selectedText, Post post)? onQuoteSelection;

  /// 图片引用回调（长按图片 → 引用）
  final void Function(String quote, Post post)? onQuoteImage;
  final bool Function(ScrollNotification) onScrollNotification;
  final ValueChanged<double>? onPointerScroll;

  /// Gap 回调（拉黑用户帖子加载）
  final void Function(int postId)? onFillGapBefore;
  final void Function(int postId)? onFillGapAfter;

  /// 展开隐藏帖子回调
  final void Function(int postId)? onExpandHiddenPost;

  /// 是否使用弹框展示回复（过滤模式下）
  final bool useReplyDialog;

  /// 查看帖子详情回调
  final void Function(Post post)? onShowPostDetail;

  /// 高亮指定用户的 boost（从 boost 通知跳转时使用）
  final String? highlightBoostUsername;
  final String? searchHighlightQuery;
  final bool enableTypingIndicator;

  const TopicPostList({
    super.key,
    required this.detail,
    required this.blockedUsernames,
    required this.scrollController,
    required this.centerKey,
    required this.headerKey,
    this.topContentInset = 0,
    this.topBoundaryHeight = kToolbarHeight,
    required this.highlightPostNumber,
    this.highlightBoostUsername,
    this.searchHighlightQuery,
    required this.isLoggedIn,
    required this.hasMoreBefore,
    required this.hasMoreAfter,
    required this.isLoadingPrevious,
    required this.isLoadingMore,
    this.incomingUnloadedPostCount = 0,
    this.isLoadMoreFailed = false,
    this.isLoadPreviousFailed = false,
    this.onRetryLoadMore,
    this.onRetryLoadPrevious,
    this.onLoadIncomingReplies,
    required this.centerPostIndex,
    required this.dividerPostIndex,
    required this.onFirstVisiblePostChanged,
    this.onVisiblePostsChanged,
    this.onScrollIndexMappingChanged,
    required this.onJumpToPost,
    required this.onReply,
    this.onReplyWithInitialContent,
    required this.onEdit,
    this.onShareAsImage,
    required this.onRefreshPost,
    required this.onVoteChanged,
    required this.onSharedIssueChanged,
    this.onNotificationLevelChanged,
    this.onSolutionChanged,
    this.onContinueAiSummary,
    this.onQuoteSelection,
    this.onQuoteImage,
    required this.onScrollNotification,
    this.onPointerScroll,
    this.onFillGapBefore,
    this.onFillGapAfter,
    this.onExpandHiddenPost,
    this.useReplyDialog = false,
    this.onShowPostDetail,
    this.enableTypingIndicator = true,
  });

  @override
  State<TopicPostList> createState() => _TopicPostListState();
}

class _TopicPostListState extends State<TopicPostList> {
  static const int _materializeStep = 4;
  static const Duration _visiblePostUpdateDelayDesktop = Duration(
    milliseconds: 240,
  );
  static const Duration _visiblePostUpdateDelayMobile = Duration(
    milliseconds: 360,
  );
  static const Duration _autoReplyResumeDelayDesktop = Duration(
    milliseconds: 220,
  );
  static const Duration _autoReplyResumeDelayMobile = Duration(
    milliseconds: 320,
  );
  static const int _maxInlineRepliesCacheEntriesMobile = 48;
  static const int _maxInlineRepliesCacheEntriesDesktop = 160;

  int? _lastReportedPostNumber;
  Timer? _visiblePostUpdateTimer;
  Timer? _autoReplyResumeTimer;
  bool _visiblePostUpdateFrameScheduled = false;
  final ValueNotifier<bool> _autoLoadRepliesPausedNotifier =
      ValueNotifier<bool>(false);
  List<_PostRenderSegment> _renderSegments = const [];
  Map<int, int> _postIndexToScrollIndex = const {};
  Map<int, int> _scrollIndexToPostNumber = const {};
  List<Post>? _visiblePostsSourcePosts;
  Set<String>? _visiblePostsSourceBlockedUsernames;
  List<Post>? _renderSegmentsSourcePosts;
  List<int>? _renderSegmentsSourceStream;
  PostStreamGaps? _renderSegmentsSourceGaps;
  Set<String>? _renderSegmentsSourceBlockedUsernames;
  List<Post> _visiblePostsCache = const [];
  Set<int> _lastVisiblePostNumbers = const <int>{};
  int? _materializeCapBefore;
  int? _materializeCapAfter;
  bool _initialMaterializationInitialized = false;
  bool _materializeTicking = false;
  bool _materializationPausedForScroll = false;
  int _parseWarmUpGeneration = 0;

  /// postNumber → postIndex 反查表（避免 indexWhere 线性查找）
  Map<int, int> _postNumberToIndex = const {};
  SelectedContent? _lastLongPostSelectedContent;
  Post? _activeLongSelectionPost;
  CodeSelectionContext? _lastLongCodeSelectionContext;
  final LinkedHashMap<int, InlineRepliesState> _inlineRepliesStateByPostNumber =
      LinkedHashMap<int, InlineRepliesState>();

  @override
  void initState() {
    super.initState();
    // 首帧渲染后触发一次可见性检测，确保进入页面时即上报阅读状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateFirstVisiblePost();
      }
    });
  }

  @override
  void didUpdateWidget(covariant TopicPostList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.id != widget.detail.id) {
      _inlineRepliesStateByPostNumber.clear();
      _lastVisiblePostNumbers = const <int>{};
      _renderSegmentsSourcePosts = null;
      _renderSegmentsSourceStream = null;
      _renderSegmentsSourceGaps = null;
      _renderSegmentsSourceBlockedUsernames = null;
      _visiblePostsSourcePosts = null;
      _visiblePostsSourceBlockedUsernames = null;
      _visiblePostsCache = const [];
      _materializeCapBefore = null;
      _materializeCapAfter = null;
      _initialMaterializationInitialized = false;
      _materializationPausedForScroll = false;
      _parseWarmUpGeneration++;
    } else if (didTopicPostCenterChange(
      oldPostNumbers: oldWidget.detail.postStream.posts
          .map((post) => post.postNumber)
          .toList(growable: false),
      oldCenterPostIndex: oldWidget.centerPostIndex,
      newPostNumbers: widget.detail.postStream.posts
          .map((post) => post.postNumber)
          .toList(growable: false),
      newCenterPostIndex: widget.centerPostIndex,
    )) {
      // 同话题显式更换中心点时，下一次 build 会先围绕新中心重建索引，
      // 再重新建立有界 cap。不能直接放开全部 segment，否则大帖跳转会在
      // 一帧内构建大量楼层和图片。prepend 仅平移索引，不会触发该分支。
      _materializeCapBefore = null;
      _materializeCapAfter = null;
      _initialMaterializationInitialized = false;
    }
  }

  @override
  void dispose() {
    _visiblePostUpdateTimer?.cancel();
    _autoReplyResumeTimer?.cancel();
    _autoLoadRepliesPausedNotifier.dispose();
    _parseWarmUpGeneration++;
    super.dispose();
  }

  // 便捷 getter，简化 widget.xxx 访问
  TopicDetail get detail => widget.detail;
  List<Post> get _visiblePosts {
    _ensureVisiblePosts();
    return _visiblePostsCache;
  }

  AutoScrollController get scrollController => widget.scrollController;
  GlobalKey get centerKey => widget.centerKey;
  GlobalKey get headerKey => widget.headerKey;
  int? get highlightPostNumber => widget.highlightPostNumber;
  bool get isLoggedIn => widget.isLoggedIn;
  bool get hasMoreBefore => widget.hasMoreBefore;
  bool get hasMoreAfter => widget.hasMoreAfter;
  bool get isLoadingPrevious => widget.isLoadingPrevious;
  bool get isLoadingMore => widget.isLoadingMore;
  int get incomingUnloadedPostCount => widget.incomingUnloadedPostCount;
  bool get isLoadMoreFailed => widget.isLoadMoreFailed;
  bool get isLoadPreviousFailed => widget.isLoadPreviousFailed;
  VoidCallback? get onRetryLoadMore => widget.onRetryLoadMore;
  VoidCallback? get onRetryLoadPrevious => widget.onRetryLoadPrevious;
  VoidCallback? get onLoadIncomingReplies => widget.onLoadIncomingReplies;
  int get centerPostIndex => widget.centerPostIndex;
  int? get dividerPostIndex => widget.dividerPostIndex;
  void Function(int postNumber) get onJumpToPost => widget.onJumpToPost;
  void Function(Post? replyToPost) get onReply => widget.onReply;
  void Function(Post post) get onEdit => widget.onEdit;
  void Function(Post post)? get onShareAsImage => widget.onShareAsImage;
  void Function(int postId) get onRefreshPost => widget.onRefreshPost;
  void Function(int, bool) get onVoteChanged => widget.onVoteChanged;
  void Function(int, bool) get onSharedIssueChanged =>
      widget.onSharedIssueChanged;
  void Function(TopicNotificationLevel)? get onNotificationLevelChanged =>
      widget.onNotificationLevelChanged;
  void Function(int postId, bool accepted)? get onSolutionChanged =>
      widget.onSolutionChanged;
  void Function(TopicSummary summary)? get onContinueAiSummary =>
      widget.onContinueAiSummary;
  void Function(String selectedText, Post post)? get onQuoteSelection =>
      widget.onQuoteSelection;
  void Function(String quote, Post post)? get onQuoteImage =>
      widget.onQuoteImage;
  bool Function(ScrollNotification) get onScrollNotification =>
      widget.onScrollNotification;
  void Function(Set<int> visiblePostNumbers)? get onVisiblePostsChanged =>
      widget.onVisiblePostsChanged;
  void Function(int postId)? get onFillGapBefore => widget.onFillGapBefore;
  void Function(int postId)? get onFillGapAfter => widget.onFillGapAfter;
  void Function(int postId)? get onExpandHiddenPost =>
      widget.onExpandHiddenPost;
  bool get useReplyDialog => widget.useReplyDialog;

  int? get _centerPostNumber =>
      centerPostIndex >= 0 && centerPostIndex < detail.postStream.posts.length
      ? detail.postStream.posts[centerPostIndex].postNumber
      : null;

  void _ensureVisiblePosts() {
    final posts = detail.postStream.posts;
    if (identical(_visiblePostsSourcePosts, posts) &&
        identical(
          _visiblePostsSourceBlockedUsernames,
          widget.blockedUsernames,
        )) {
      return;
    }

    _visiblePostsCache = BlockedUserFilter.visiblePosts(
      detail.postStream.posts,
      widget.blockedUsernames,
    );
    _visiblePostsSourcePosts = posts;
    _visiblePostsSourceBlockedUsernames = widget.blockedUsernames;
  }

  ({double top, double bottom})? _resolveTagBounds(
    int scrollIndex,
    List<int> staleTagKeys,
  ) {
    final tag = scrollController.tagMap[scrollIndex];
    if (tag == null) {
      staleTagKeys.add(scrollIndex);
      return null;
    }

    final ctx = tag.context;
    if (!ctx.mounted) {
      staleTagKeys.add(scrollIndex);
      return null;
    }

    final RenderBox? renderBox;
    try {
      renderBox = ctx.findRenderObject() as RenderBox?;
    } catch (_) {
      staleTagKeys.add(scrollIndex);
      return null;
    }
    if (renderBox == null || !renderBox.hasSize || !renderBox.attached) {
      staleTagKeys.add(scrollIndex);
      return null;
    }

    final topY = renderBox.localToGlobal(Offset.zero).dy;
    return (top: topY, bottom: topY + renderBox.size.height);
  }

  /// 检测当前可见帖子（Eyeline 机制）
  ///
  /// 参考 Discourse 官方实现（post-stream-viewport-tracker.js）的 eyeline 算法：
  /// Eyeline 是一条虚拟水平线，代表用户"正在看"的位置。
  /// - 大部分滚动过程中，eyeline 固定在视口顶部，当前帖子即顶部帖子
  /// - 接近底部的最后一个视口距离内，eyeline 逐渐从顶部移向底部
  /// - 滚到最底时，eyeline 在视口底部，确保能显示最后一个帖子
  /// 这使得进度指示器在整个滚动过程中平滑过渡，无需硬编码特殊情况。
  void _updateFirstVisiblePost() {
    final posts = _visiblePosts;
    if (posts.isEmpty) return;

    final tagMap = scrollController.tagMap;
    if (tagMap.isEmpty) return;

    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    final viewportHeight = position.viewportDimension;

    // 视口可见区域的上下边界
    final topBoundary =
        widget.topBoundaryHeight + MediaQuery.of(context).padding.top;
    final bottomBoundary = viewportHeight;

    // === 计算 eyeline 位置 ===
    double eyeline;
    if (hasMoreAfter) {
      // 还有更多帖子未加载，eyeline 固定在顶部（标准行为）
      eyeline = topBoundary;
    } else {
      // 所有帖子已加载，根据滚动进度动态计算 eyeline
      final remainingScroll = position.maxScrollExtent - position.pixels;
      final totalScrollRange =
          position.maxScrollExtent - position.minScrollExtent;
      // eyeline 在最后一个视口距离内从顶部过渡到底部
      final scrollableArea = viewportHeight.clamp(0.0, totalScrollRange);
      final progress = scrollableArea > 0
          ? (1 - (remainingScroll / scrollableArea).clamp(0.0, 1.0))
          : 1.0;
      eyeline = topBoundary + progress * (bottomBoundary - topBoundary);
    }

    // === 找到 eyeline 所在的帖子并收集可见帖子 ===
    int? eyelinePostIndex;
    final visiblePostNumbers = <int>{};
    double closestDistance = double.infinity;
    int? closestPostIndex;
    final staleTagKeys = <int>[];

    final sortedKeys = tagMap.keys.toList(growable: false)..sort();

    for (int index = 0; index < sortedKeys.length;) {
      final key = sortedKeys[index];
      final postNumber = _scrollIndexToPostNumber[key];
      if (postNumber == null) {
        staleTagKeys.add(key);
        index += 1;
        continue;
      }

      var groupEnd = index;
      while (groupEnd + 1 < sortedKeys.length &&
          _scrollIndexToPostNumber[sortedKeys[groupEnd + 1]] == postNumber) {
        groupEnd += 1;
      }

      ({double top, double bottom})? firstBounds;
      int? firstValidIndex;
      for (int cursor = index; cursor <= groupEnd; cursor++) {
        final bounds = _resolveTagBounds(sortedKeys[cursor], staleTagKeys);
        if (bounds != null) {
          firstBounds = bounds;
          firstValidIndex = cursor;
          break;
        }
      }

      if (firstBounds == null) {
        index = groupEnd + 1;
        continue;
      }

      ({double top, double bottom}) lastBounds;
      if (firstValidIndex == groupEnd) {
        lastBounds = firstBounds;
      } else {
        ({double top, double bottom})? resolvedLastBounds;
        for (int cursor = groupEnd; cursor >= firstValidIndex!; cursor--) {
          final bounds = _resolveTagBounds(sortedKeys[cursor], staleTagKeys);
          if (bounds != null) {
            resolvedLastBounds = bounds;
            break;
          }
        }
        lastBounds = resolvedLastBounds ?? firstBounds;
      }

      final topY = firstBounds.top;
      final bottomY = lastBounds.bottom;

      // 收集可见帖子（帖子与视口有交集）
      if (topY < viewportHeight && bottomY > topBoundary) {
        visiblePostNumbers.add(postNumber);
      }

      // 帖子包含 eyeline → 即为当前帖子
      if (topY <= eyeline && bottomY > eyeline) {
        eyelinePostIndex = _postNumberToIndex[postNumber];
      }

      // 记录距 eyeline 最近的帖子（兜底用）
      final distance = topY > eyeline
          ? topY - eyeline
          : (bottomY < eyeline ? eyeline - bottomY : 0.0);
      if (distance < closestDistance) {
        closestDistance = distance;
        closestPostIndex = _postNumberToIndex[postNumber];
      }

      index = groupEnd + 1;
    }

    if (staleTagKeys.isNotEmpty) {
      for (final key in staleTagKeys) {
        tagMap.remove(key);
      }
    }

    // 没有帖子包含 eyeline 时（如处于帖子间隙或底部留白），取最近的帖子
    eyelinePostIndex ??= closestPostIndex;

    // 通知可见帖子变化（用于 screenTrack）
    if (visiblePostNumbers.isNotEmpty &&
        !setEquals(_lastVisiblePostNumbers, visiblePostNumbers)) {
      _lastVisiblePostNumbers = Set<int>.unmodifiable(visiblePostNumbers);
      onVisiblePostsChanged?.call(visiblePostNumbers);
    } else if (visiblePostNumbers.isEmpty &&
        _lastVisiblePostNumbers.isNotEmpty) {
      _lastVisiblePostNumbers = const <int>{};
    }

    if (eyelinePostIndex != null) {
      final reportPostNumber = posts[eyelinePostIndex].postNumber;

      // 防止重复报告相同的帖子
      if (reportPostNumber != _lastReportedPostNumber) {
        _lastReportedPostNumber = reportPostNumber;
        widget.onFirstVisiblePostChanged(reportPostNumber);
      }
    }
  }

  /// 处理滚动通知，同时更新可见帖子
  bool _handleScrollNotification(ScrollNotification notification) {
    // 先调用原有的滚动通知处理
    final result = onScrollNotification(notification);

    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification) {
      _setAutoLoadRepliesPaused(true);
      _materializationPausedForScroll = true;
    }
    if (notification is ScrollUpdateNotification) {
      _scheduleVisiblePostUpdate();
    } else if (notification is ScrollEndNotification) {
      _materializationPausedForScroll = false;
      _scheduleMaterializeStep();
      _resumeAutoLoadReplies();
      _scheduleVisiblePostUpdate(immediate: true);
    }

    return result;
  }

  void _setAutoLoadRepliesPaused(bool paused) {
    _autoReplyResumeTimer?.cancel();
    if (_autoLoadRepliesPausedNotifier.value == paused) return;
    _autoLoadRepliesPausedNotifier.value = paused;
  }

  void _resumeAutoLoadReplies() {
    _autoReplyResumeTimer?.cancel();
    _autoReplyResumeTimer = Timer(_autoReplyResumeDelay, () {
      if (!mounted || !_autoLoadRepliesPausedNotifier.value) return;
      _autoLoadRepliesPausedNotifier.value = false;
      VisibilityDetectorController.instance.notifyNow();
    });
  }

  void _scheduleVisiblePostUpdate({bool immediate = false}) {
    if (immediate) {
      _visiblePostUpdateTimer?.cancel();
      _visiblePostUpdateTimer = null;
      _scheduleVisiblePostUpdateFrame();
      return;
    }

    if (_visiblePostUpdateFrameScheduled) {
      return;
    }

    _visiblePostUpdateTimer?.cancel();
    _visiblePostUpdateTimer = Timer(_visiblePostUpdateDelay, () {
      _visiblePostUpdateTimer = null;
      _scheduleVisiblePostUpdateFrame();
    });
  }

  void _scheduleVisiblePostUpdateFrame() {
    if (_visiblePostUpdateFrameScheduled) return;
    _visiblePostUpdateFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visiblePostUpdateFrameScheduled = false;
      if (mounted) _updateFirstVisiblePost();
    });
  }

  int get _maxInlineRepliesCacheEntries => Responsive.isMobile(context)
      ? _maxInlineRepliesCacheEntriesMobile
      : _maxInlineRepliesCacheEntriesDesktop;

  Duration get _visiblePostUpdateDelay => Responsive.isMobile(context)
      ? _visiblePostUpdateDelayMobile
      : _visiblePostUpdateDelayDesktop;

  Duration get _autoReplyResumeDelay => Responsive.isMobile(context)
      ? _autoReplyResumeDelayMobile
      : _autoReplyResumeDelayDesktop;

  InlineRepliesState? _inlineRepliesStateFor(int postNumber) {
    final state = _inlineRepliesStateByPostNumber.remove(postNumber);
    if (state != null) {
      _inlineRepliesStateByPostNumber[postNumber] = state;
    }
    return state;
  }

  void _rememberInlineRepliesState(int postNumber, InlineRepliesState state) {
    _inlineRepliesStateByPostNumber.remove(postNumber);
    _inlineRepliesStateByPostNumber[postNumber] = state;
    while (_inlineRepliesStateByPostNumber.length >
        _maxInlineRepliesCacheEntries) {
      _inlineRepliesStateByPostNumber.remove(
        _inlineRepliesStateByPostNumber.keys.first,
      );
    }
  }

  String _segmentKey(_PostRenderSegment segment) {
    switch (segment.type) {
      case _PostRenderSegmentType.shortPost:
        return topicPostRenderIdentityKey(
          topicId: detail.id,
          postNumber: segment.post.postNumber,
          segmentType: 'post',
        );
      case _PostRenderSegmentType.longHeader:
        return topicPostRenderIdentityKey(
          topicId: detail.id,
          postNumber: segment.post.postNumber,
          segmentType: 'long-header',
        );
      case _PostRenderSegmentType.longChunk:
        return topicPostRenderIdentityKey(
          topicId: detail.id,
          postNumber: segment.post.postNumber,
          segmentType: 'long-chunk',
          chunkIndex: segment.chunkIndex,
        );
      case _PostRenderSegmentType.longFooter:
        return topicPostRenderIdentityKey(
          topicId: detail.id,
          postNumber: segment.post.postNumber,
          segmentType: 'long-footer',
        );
      case _PostRenderSegmentType.gapBefore:
        return topicPostRenderIdentityKey(
          topicId: detail.id,
          postNumber: segment.post.postNumber,
          segmentType: 'gap-before',
        );
      case _PostRenderSegmentType.gapAfter:
        return topicPostRenderIdentityKey(
          topicId: detail.id,
          postNumber: segment.post.postNumber,
          segmentType: 'gap-after',
        );
    }
  }

  /// 在大屏上为内容添加宽度约束
  Widget _wrapContent(BuildContext context, Widget child) {
    if (Responsive.isMobile(context)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: Breakpoints.maxContentWidth,
        ),
        child: child,
      ),
    );
  }

  bool _hasSameRenderSegmentsSource(List<Post> posts) {
    return identical(_renderSegmentsSourcePosts, posts) &&
        identical(_renderSegmentsSourceStream, detail.postStream.stream) &&
        identical(_renderSegmentsSourceGaps, detail.postStream.gaps) &&
        identical(
          _renderSegmentsSourceBlockedUsernames,
          widget.blockedUsernames,
        );
  }

  void _ensureRenderSegments(List<Post> posts) {
    if (_hasSameRenderSegmentsSource(posts)) {
      return;
    }
    final diagnostics = PerformanceDiagnosticsService.instance;
    final segmentsTimer = diagnostics.startSyncWork();
    final oldPosts = _renderSegmentsSourcePosts;
    final oldSegmentCount = _renderSegments.length;
    final oldCenterPostNumber = _centerPostNumber;
    final oldCenterVisibleIndex = oldCenterPostNumber == null
        ? null
        : _postNumberToIndex[oldCenterPostNumber];
    final oldCenterScrollIndex = oldCenterVisibleIndex == null
        ? -1
        : (_postIndexToScrollIndex[oldCenterVisibleIndex] ?? -1);
    final segments = <_PostRenderSegment>[];
    final postIndexToScrollIndex = <int, int>{};
    final scrollIndexToPostNumber = <int, int>{};
    final postNumberToIndex = <int, int>{};
    final gaps = detail.postStream.gaps;

    for (int postIndex = 0; postIndex < posts.length; postIndex++) {
      final post = posts[postIndex];

      // 检查此帖子前面是否有 gap
      if (gaps != null && gaps.before.containsKey(post.id)) {
        final gapIds = gaps.before[post.id]!;
        if (gapIds.isNotEmpty) {
          scrollIndexToPostNumber[segments.length] = post.postNumber;
          segments.add(
            _PostRenderSegment.gapBefore(
              scrollIndex: segments.length,
              postIndex: postIndex,
              post: post,
              gapCount: gapIds.length,
            ),
          );
        }
      }

      final renderData = LongPostRenderData.fromHtml(post.cooked);
      final useLongSegments = renderData.chunks.isNotEmpty;

      postIndexToScrollIndex[postIndex] = segments.length;
      postNumberToIndex[post.postNumber] = postIndex;

      if (!useLongSegments) {
        scrollIndexToPostNumber[segments.length] = post.postNumber;
        segments.add(
          _PostRenderSegment.shortPost(
            scrollIndex: segments.length,
            postIndex: postIndex,
            post: post,
          ),
        );
      } else {
        scrollIndexToPostNumber[segments.length] = post.postNumber;
        segments.add(
          _PostRenderSegment.header(
            scrollIndex: segments.length,
            postIndex: postIndex,
            post: post,
          ),
        );

        for (final chunk in renderData.chunks) {
          scrollIndexToPostNumber[segments.length] = post.postNumber;
          segments.add(
            _PostRenderSegment.chunk(
              scrollIndex: segments.length,
              postIndex: postIndex,
              post: post,
              chunkIndex: chunk.index,
              chunkData: chunk,
              renderData: renderData,
            ),
          );
        }

        scrollIndexToPostNumber[segments.length] = post.postNumber;
        segments.add(
          _PostRenderSegment.footer(
            scrollIndex: segments.length,
            postIndex: postIndex,
            post: post,
          ),
        );
      }

      // 检查此帖子后面是否有 gap
      if (gaps != null && gaps.after.containsKey(post.id)) {
        final gapIds = gaps.after[post.id]!;
        if (gapIds.isNotEmpty) {
          scrollIndexToPostNumber[segments.length] = post.postNumber;
          segments.add(
            _PostRenderSegment.gapAfter(
              scrollIndex: segments.length,
              postIndex: postIndex,
              post: post,
              gapCount: gapIds.length,
            ),
          );
        }
      }
    }

    _renderSegments = segments;
    _postIndexToScrollIndex = postIndexToScrollIndex;
    _scrollIndexToPostNumber = scrollIndexToPostNumber;
    _postNumberToIndex = postNumberToIndex;
    _renderSegmentsSourcePosts = posts;
    _renderSegmentsSourceStream = detail.postStream.stream;
    _renderSegmentsSourceGaps = detail.postStream.gaps;
    _renderSegmentsSourceBlockedUsernames = widget.blockedUsernames;
    diagnostics.finishSyncWork(
      segmentsTimer,
      label: 'topic:segments',
      data: <String, Object?>{
        'topicId': detail.id,
        'posts': posts.length,
        'segments': segments.length,
      },
    );
    widget.onScrollIndexMappingChanged?.call(postIndexToScrollIndex);
    _handlePostGrowth(
      oldPosts: oldPosts,
      newPosts: posts,
      oldSegmentCount: oldSegmentCount,
      oldCenterScrollIndex: oldCenterScrollIndex,
    );
  }

  void _handlePostGrowth({
    required List<Post>? oldPosts,
    required List<Post> newPosts,
    required int oldSegmentCount,
    required int oldCenterScrollIndex,
  }) {
    final growth = detectTopicPostGrowth(
      oldPostIds: oldPosts?.map((post) => post.id).toList(growable: false),
      newPostIds: newPosts.map((post) => post.id).toList(growable: false),
    );
    if (growth == null || oldPosts == null) return;

    final addedPostCount = newPosts.length - oldPosts.length;
    final addedPosts = switch (growth) {
      TopicPostGrowth.append => newPosts.sublist(oldPosts.length),
      TopicPostGrowth.prepend => newPosts.sublist(0, addedPostCount),
    };
    _schedulePostParseWarmUp(addedPosts);

    final plan = planTopicPostPagingMaterialization(
      growth: growth,
      oldSegmentCount: oldSegmentCount,
      newSegmentCount: _renderSegments.length,
      oldCenterScrollIndex: oldCenterScrollIndex,
      step: _materializeStep,
    );
    if (plan == null) return;

    switch (plan.side) {
      case TopicPostMaterializationSide.before:
        _materializeCapBefore ??= plan.initialCap;
      case TopicPostMaterializationSide.after:
        _materializeCapAfter ??= plan.initialCap;
    }
    _scheduleMaterializeStep();
  }

  void _initializeMaterialization(int centerScrollIndex) {
    if (_initialMaterializationInitialized) return;
    _initialMaterializationInitialized = true;
    final initial = initialTopicPostMaterialization(
      segmentPostIds: _renderSegments
          .map((segment) => segment.post.id)
          .toList(growable: false),
      centerScrollIndex: centerScrollIndex,
      step: _materializeStep,
    );
    _materializeCapBefore = initial.beforeCap;
    _materializeCapAfter = initial.afterCap;
    _scheduleMaterializeStep();
  }

  void _scheduleMaterializeStep() {
    if (_materializeTicking) return;
    _materializeTicking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _materializeTicking = false;
      if (!mounted || !_initialMaterializationInitialized) return;
      if (!shouldAdvanceTopicPostMaterialization(
        isScrollActive: _materializationPausedForScroll,
        hasPendingMaterialization:
            _materializeCapBefore != null || _materializeCapAfter != null,
      )) {
        return;
      }

      final centerPostNumber = _centerPostNumber;
      final centerVisibleIndex = centerPostNumber == null
          ? null
          : _postNumberToIndex[centerPostNumber];
      final centerScrollIndex = centerVisibleIndex == null
          ? 0
          : (_postIndexToScrollIndex[centerVisibleIndex] ?? 0);
      final beforeTotal = centerScrollIndex;
      final afterTotal = _renderSegments.length - centerScrollIndex;
      var advanced = false;

      final capBefore = _materializeCapBefore;
      if (capBefore != null) {
        if (capBefore >= beforeTotal) {
          _materializeCapBefore = null;
        } else {
          _materializeCapBefore = capBefore + _materializeStep;
          advanced = true;
        }
      }

      final capAfter = _materializeCapAfter;
      if (capAfter != null) {
        if (capAfter >= afterTotal) {
          _materializeCapAfter = null;
        } else {
          _materializeCapAfter = capAfter + _materializeStep;
          advanced = true;
        }
      }

      if (advanced) {
        setState(() {});
        _scheduleMaterializeStep();
      }
    });
  }

  void _schedulePostParseWarmUp(List<Post> posts) {
    if (posts.isEmpty) return;
    final generation = ++_parseWarmUpGeneration;
    var index = 0;

    void step() {
      SchedulerBinding.instance.scheduleTask<void>(() async {
        if (!mounted || generation != _parseWarmUpGeneration) return;
        final post = posts[index++];
        try {
          if (post.cooked.length > ChunkedHtmlContent.chunkThreshold) {
            await HtmlChunkCache.instance.parseAsync(post.cooked);
            if (!mounted || generation != _parseWarmUpGeneration) return;
            LongPostRenderData.fromHtml(post.cooked);
          } else {
            GalleryInfo.fromHtml(post.cooked);
          }
        } catch (_) {
          // 预热失败不影响正式渲染，进入视口时仍走现有同步兜底。
        }
        if (mounted &&
            generation == _parseWarmUpGeneration &&
            index < posts.length) {
          step();
        }
      }, Priority.idle);
    }

    step();
  }

  void _rememberLongSelectionPost(Post post) {
    _activeLongSelectionPost = post;
    CodeSelectionContextTracker.instance.clear();
  }

  @override
  Widget build(BuildContext context) {
    PerformanceDiagnosticsService.instance.noteBuild(
      'topic:postList',
      id: detail.id,
    );
    final posts = _visiblePosts;
    final cacheExtent = Responsive.isMobile(context) ? 160.0 : 500.0;
    final scrollPhysics = Theme.of(context).platform == TargetPlatform.iOS
        ? const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics())
        : const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics());
    final hasFirstPost = posts.isNotEmpty && posts.first.postNumber == 1;
    _ensureRenderSegments(posts);
    final centerPostNumber = _centerPostNumber;
    final centerVisibleIndex = centerPostNumber == null
        ? null
        : _postNumberToIndex[centerPostNumber];
    final centerScrollIndex = centerVisibleIndex == null
        ? 0
        : (_postIndexToScrollIndex[centerVisibleIndex] ?? 0);
    _initializeMaterialization(centerScrollIndex);

    return LazyLoadPauseScope(
      notifier: _autoLoadRepliesPausedNotifier,
      child: SelectionArea(
        onSelectionChanged: (content) {
          _lastLongPostSelectedContent = content;
          QuoteSelectionHelper.updateSelectionActive(content?.plainText);
          _lastLongCodeSelectionContext =
              CodeSelectionContextTracker.instance.current;
          if (content == null) {
            _activeLongSelectionPost = null;
            _lastLongCodeSelectionContext = null;
          }
        },
        contextMenuBuilder: (context, state) {
          final items = QuoteSelectionHelper.buildMenuItems(
            baseItems: state.contextMenuButtonItems,
            plainText: _lastLongPostSelectedContent?.plainText,
            post: _activeLongSelectionPost,
            hideToolbar: state.hideToolbar,
            topicId: detail.id,
            onQuoteSelection: onQuoteSelection,
            onSearchSelection: (text) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SearchPage(initialQuery: text),
                ),
              );
            },
            codeContext: _lastLongCodeSelectionContext,
          );
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: state.contextMenuAnchors,
            buttonItems: items,
          );
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                widget.onPointerScroll?.call(event.scrollDelta.dy);
              }
            },
            child: CustomScrollView(
              controller: scrollController,
              center: centerKey,
              cacheExtent: cacheExtent,
              physics: scrollPhysics,
              slivers: [
                // 向上加载骨架屏 / 失败重试
                if (hasMoreBefore && isLoadPreviousFailed)
                  SliverToBoxAdapter(
                    child: _LoadFailedRetry(onRetry: onRetryLoadPrevious),
                  )
                else if (hasMoreBefore && isLoadingPrevious)
                  SliverToBoxAdapter(
                    child: _wrapContent(context, const _LoadMoreIndicator()),
                  ),

                // 话题 Header（centerPostIndex > 0 时放在 before-center 区域）
                if (hasFirstPost &&
                    centerPostIndex > 0 &&
                    widget.topContentInset > 0)
                  SliverToBoxAdapter(
                    child: SizedBox(height: widget.topContentInset),
                  ),
                if (hasFirstPost && centerPostIndex > 0)
                  SliverToBoxAdapter(
                    child: _wrapContent(
                      context,
                      SelectionContainer.disabled(
                        child: TopicDetailHeader(
                          detail: detail,
                          headerKey: headerKey,
                          onVoteChanged: onVoteChanged,
                          onNotificationLevelChanged:
                              onNotificationLevelChanged,
                          onJumpToPost: onJumpToPost,
                          onContinueAiSummary: onContinueAiSummary,
                        ),
                      ),
                    ),
                  ),
                if (incomingUnloadedPostCount > 0)
                  SliverToBoxAdapter(
                    child: _wrapContent(
                      context,
                      SelectionContainer.disabled(
                        child: _IncomingRepliesIndicator(
                          count: incomingUnloadedPostCount,
                          onTap: isLoadingMore ? null : onLoadIncomingReplies,
                        ),
                      ),
                    ),
                  ),

                // Before-center 帖子（SliverList.builder 实现虚拟化回收）
                // center 之前的 sliver 向上增长，index 0 离 center 最近，需要反转映射
                if (centerPostIndex > 0)
                  SliverList.builder(
                    itemCount: materializedSegmentCount(
                      total: centerScrollIndex,
                      cap: _materializeCapBefore,
                    ),
                    itemBuilder: (context, index) {
                      final segmentIndex = centerScrollIndex - 1 - index;
                      return _buildSegmentItem(
                        context,
                        _renderSegments[segmentIndex],
                      );
                    },
                  ),

                // 中心帖子 + after-center 帖子（合并为一个 SliverList.builder）
                // SliverList 不会回收最后一个 child，所以必须合并，确保 center 帖子
                // 是多 item 列表中的一项，滚出视口后能被正常回收。
                // centerPostIndex == 0 且有 header 时，用 SliverMainAxisGroup 将
                // header 和帖子列表组合为 center，保证 header 默认可见。
                if (centerPostIndex == 0 && hasFirstPost)
                  SliverMainAxisGroup(
                    key: centerKey,
                    slivers: [
                      if (widget.topContentInset > 0)
                        SliverToBoxAdapter(
                          child: SizedBox(height: widget.topContentInset),
                        ),
                      SliverToBoxAdapter(
                        child: _wrapContent(
                          context,
                          SelectionContainer.disabled(
                            child: TopicDetailHeader(
                              detail: detail,
                              headerKey: headerKey,
                              onVoteChanged: onVoteChanged,
                              onNotificationLevelChanged:
                                  onNotificationLevelChanged,
                              onJumpToPost: onJumpToPost,
                              onContinueAiSummary: onContinueAiSummary,
                            ),
                          ),
                        ),
                      ),
                      if (incomingUnloadedPostCount > 0)
                        SliverToBoxAdapter(
                          child: _wrapContent(
                            context,
                            SelectionContainer.disabled(
                              child: _IncomingRepliesIndicator(
                                count: incomingUnloadedPostCount,
                                onTap: isLoadingMore
                                    ? null
                                    : onLoadIncomingReplies,
                              ),
                            ),
                          ),
                        ),
                      SliverList.builder(
                        itemCount: materializedSegmentCount(
                          total: _renderSegments.length,
                          cap: _materializeCapAfter,
                        ),
                        itemBuilder: (context, index) =>
                            _buildSegmentItem(context, _renderSegments[index]),
                      ),
                    ],
                  )
                else
                  SliverList.builder(
                    key: centerKey,
                    itemCount: materializedSegmentCount(
                      total: _renderSegments.length - centerScrollIndex,
                      cap: _materializeCapAfter,
                    ),
                    itemBuilder: (context, index) {
                      final segmentIndex = centerScrollIndex + index;
                      return _buildSegmentItem(
                        context,
                        _renderSegments[segmentIndex],
                      );
                    },
                  ),

                // 正在输入指示器（始终占位，通过 AnimatedSize 平滑过渡避免列表抖动）
                if (!hasMoreAfter)
                  SliverToBoxAdapter(
                    child: _wrapContent(
                      context,
                      SelectionContainer.disabled(
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          alignment: Alignment.topCenter,
                          child: widget.enableTypingIndicator
                              ? Consumer(
                                  builder: (context, ref, _) {
                                    final typingUsers = ref.watch(
                                      topicChannelProvider(
                                        detail.id,
                                      ).select((s) => s.typingUsers),
                                    );
                                    return TypingAvatars(users: typingUsers);
                                  },
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),

                // 底部加载骨架屏 / 失败重试
                if (hasMoreAfter && isLoadMoreFailed)
                  SliverToBoxAdapter(
                    child: _LoadFailedRetry(onRetry: onRetryLoadMore),
                  )
                else if (hasMoreAfter && isLoadingMore)
                  SliverToBoxAdapter(
                    child: _wrapContent(context, const _LoadMoreIndicator()),
                  ),
                SliverPadding(
                  padding: EdgeInsets.only(
                    bottom: 80 + MediaQuery.of(context).padding.bottom,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 判断是否需要显示日期分割线
  bool _shouldShowDateSeparator(int postIndex) {
    final posts = _visiblePosts;
    if (postIndex <= 0) return false;

    final currentDate = posts[postIndex].createdAt;
    final previousDate = posts[postIndex - 1].createdAt;

    final currentDay = DateTime(
      currentDate.year,
      currentDate.month,
      currentDate.day,
    );
    final previousDay = DateTime(
      previousDate.year,
      previousDate.month,
      previousDate.day,
    );

    return currentDay != previousDay;
  }

  Widget _buildSegmentItem(BuildContext context, _PostRenderSegment segment) {
    final post = segment.post;
    final postIndex = segment.postIndex;
    final showDivider = dividerPostIndex == postIndex;
    final showTopSeparator = _shouldShowDateSeparator(postIndex);
    final dateSeparatorLabel = showTopSeparator
        ? TimeUtils.formatSmartDate(post.createdAt)
        : null;
    final posts_ = _visiblePosts;
    final nextPostIndex = postIndex + 1;
    final showBottomSeparator =
        nextPostIndex < posts_.length &&
        _shouldShowDateSeparator(nextPostIndex);
    final bottomDateSeparatorLabel = showBottomSeparator
        ? TimeUtils.formatSmartDate(posts_[nextPostIndex].createdAt)
        : null;
    final isTargetPost = highlightPostNumber == post.postNumber;
    final boostUsername = isTargetPost ? widget.highlightBoostUsername : null;
    // 能匹配到具体 boost 时不高亮帖子，匹配不到时回退到高亮帖子
    final canLocateBoost =
        boostUsername != null &&
        BlockedUserFilter.visibleBoosts(
          post.boosts ?? const <Boost>[],
          widget.blockedUsernames,
        ).any((b) => b.user.username == boostUsername);
    final highlight = isTargetPost && !canLocateBoost;
    final Widget child;

    switch (segment.type) {
      case _PostRenderSegmentType.shortPost:
        child = PostItem(
          post: post,
          topicId: detail.id,
          highlight: highlight,
          highlightBoostUsername: boostUsername,
          isTopicOwner: detail.createdBy?.username == post.username,
          topicHasAcceptedAnswer: detail.hasAcceptedAnswer,
          acceptedAnswers: detail.acceptedAnswers,
          dateSeparatorLabel: dateSeparatorLabel,
          bottomDateSeparatorLabel: bottomDateSeparatorLabel,
          onLike: () => ToastService.showInfo(S.current.ai_likeInDev),
          onReply: isLoggedIn
              ? () => onReply(post.postNumber == 1 ? null : post)
              : null,
          onReplyWithInitialContent:
              isLoggedIn && widget.onReplyWithInitialContent != null
              ? (initialContent) => widget.onReplyWithInitialContent!(
                  post.postNumber == 1 ? null : post,
                  initialContent,
                )
              : null,
          onEdit: isLoggedIn && post.canEdit ? () => onEdit(post) : null,
          onShareAsImage: onShareAsImage != null
              ? () => onShareAsImage!(post)
              : null,
          onRefreshPost: onRefreshPost,
          onJumpToPost: onJumpToPost,
          onSolutionChanged: onSolutionChanged,
          onQuoteSelection: onQuoteSelection,
          onQuoteImage: onQuoteImage,
          onExpandHiddenPost: onExpandHiddenPost,
          useReplyDialog: useReplyDialog,
          onShowPostDetail: widget.onShowPostDetail != null
              ? () => widget.onShowPostDetail!(post)
              : null,
          inlineRepliesState: _inlineRepliesStateFor(post.postNumber),
          onInlineRepliesStateChanged: (state) {
            _rememberInlineRepliesState(post.postNumber, state);
          },
          sharedIssueVisible: post.postNumber == 1 && detail.sharedIssueVisible,
          canCreateSharedIssue: detail.canCreateSharedIssue,
          sharedIssueCount: detail.sharedIssueCount,
          userCreatedSharedIssue: detail.userCreatedSharedIssue,
          onSharedIssueChanged: onSharedIssueChanged,
          searchHighlightQuery: widget.searchHighlightQuery,
          autoLoadRepliesPausedListenable: _autoLoadRepliesPausedNotifier,
          blockedUsernames: widget.blockedUsernames,
          enableContentSelectionArea: false,
          useUsernameAsPrimaryLabel: post.postNumber == 1,
        );
        break;
      case _PostRenderSegmentType.longHeader:
        child = LongPostHeaderSegment(
          post: post,
          topicId: detail.id,
          highlight: highlight,
          isTopicOwner: detail.createdBy?.username == post.username,
          dateSeparatorLabel: dateSeparatorLabel,
          showDivider: showDivider,
          onJumpToPost: onJumpToPost,
          useUsernameAsPrimaryLabel: post.postNumber == 1,
        );
        break;
      case _PostRenderSegmentType.longChunk:
        child = LongPostChunkSegment(
          post: post,
          topicId: detail.id,
          highlight: highlight,
          chunk: segment.chunkData!,
          renderData: segment.renderData!,
          onQuoteImage: onQuoteImage,
          onJumpToPost: onJumpToPost,
          searchHighlightQuery: widget.searchHighlightQuery,
        );
        break;
      case _PostRenderSegmentType.longFooter:
        child = LongPostFooterSegment(
          post: post,
          topicId: detail.id,
          highlight: highlight,
          highlightBoostUsername: boostUsername,
          topicHasAcceptedAnswer: detail.hasAcceptedAnswer,
          acceptedAnswers: detail.acceptedAnswers,
          bottomDateSeparatorLabel: bottomDateSeparatorLabel,
          onReply: isLoggedIn
              ? () => onReply(post.postNumber == 1 ? null : post)
              : null,
          onReplyWithInitialContent:
              isLoggedIn && widget.onReplyWithInitialContent != null
              ? (initialContent) => widget.onReplyWithInitialContent!(
                  post.postNumber == 1 ? null : post,
                  initialContent,
                )
              : null,
          onEdit: isLoggedIn && post.canEdit ? () => onEdit(post) : null,
          onShareAsImage: onShareAsImage != null
              ? () => onShareAsImage!(post)
              : null,
          onRefreshPost: onRefreshPost,
          onJumpToPost: onJumpToPost,
          onSolutionChanged: onSolutionChanged,
          useReplyDialog: useReplyDialog,
          onShowPostDetail: widget.onShowPostDetail != null
              ? () => widget.onShowPostDetail!(post)
              : null,
          inlineRepliesState: _inlineRepliesStateFor(post.postNumber),
          onInlineRepliesStateChanged: (state) {
            _rememberInlineRepliesState(post.postNumber, state);
          },
          sharedIssueVisible: post.postNumber == 1 && detail.sharedIssueVisible,
          canCreateSharedIssue: detail.canCreateSharedIssue,
          sharedIssueCount: detail.sharedIssueCount,
          userCreatedSharedIssue: detail.userCreatedSharedIssue,
          onSharedIssueChanged: onSharedIssueChanged,
          autoLoadRepliesPausedListenable: _autoLoadRepliesPausedNotifier,
          blockedUsernames: widget.blockedUsernames,
        );
        break;
      case _PostRenderSegmentType.gapBefore:
        child = SelectionContainer.disabled(
          child: _GapIndicator(
            count: segment.gapCount,
            onTap: onFillGapBefore != null
                ? () => onFillGapBefore!(post.id)
                : null,
          ),
        );
        break;
      case _PostRenderSegmentType.gapAfter:
        child = SelectionContainer.disabled(
          child: _GapIndicator(
            count: segment.gapCount,
            onTap: onFillGapAfter != null
                ? () => onFillGapAfter!(post.id)
                : null,
          ),
        );
        break;
    }

    final tagChild = segment.type == _PostRenderSegmentType.shortPost
        ? child
        : Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _rememberLongSelectionPost(post),
            child: child,
          );
    final wrapped = _wrapContent(
      context,
      AutoScrollTag(
        key: ValueKey(_segmentKey(segment)),
        controller: scrollController,
        index: segment.scrollIndex,
        // 帖子高亮由 PostItem 自己处理，直通现有 child，避免每个 segment
        // 常驻默认 DecoratedBoxTransition 和 DecorationTween。
        builder: (context, animation) => tagChild,
      ),
    );

    return wrapped;
  }
}

enum _PostRenderSegmentType {
  shortPost,
  longHeader,
  longChunk,
  longFooter,
  gapBefore,
  gapAfter,
}

class _PostRenderSegment {
  final _PostRenderSegmentType type;
  final int scrollIndex;
  final int postIndex;
  final Post post;
  final int? chunkIndex;
  final HtmlChunk? chunkData;
  final LongPostRenderData? renderData;
  final int gapCount; // gap 段中隐藏帖子的数量

  const _PostRenderSegment._({
    required this.type,
    required this.scrollIndex,
    required this.postIndex,
    required this.post,
    this.chunkIndex,
    this.chunkData,
    this.renderData,
    this.gapCount = 0,
  });
  factory _PostRenderSegment.shortPost({
    required int scrollIndex,
    required int postIndex,
    required Post post,
  }) {
    return _PostRenderSegment._(
      type: _PostRenderSegmentType.shortPost,
      scrollIndex: scrollIndex,
      postIndex: postIndex,
      post: post,
    );
  }

  factory _PostRenderSegment.header({
    required int scrollIndex,
    required int postIndex,
    required Post post,
  }) {
    return _PostRenderSegment._(
      type: _PostRenderSegmentType.longHeader,
      scrollIndex: scrollIndex,
      postIndex: postIndex,
      post: post,
    );
  }

  factory _PostRenderSegment.chunk({
    required int scrollIndex,
    required int postIndex,
    required Post post,
    required int chunkIndex,
    required HtmlChunk chunkData,
    required LongPostRenderData renderData,
  }) {
    return _PostRenderSegment._(
      type: _PostRenderSegmentType.longChunk,
      scrollIndex: scrollIndex,
      postIndex: postIndex,
      post: post,
      chunkIndex: chunkIndex,
      chunkData: chunkData,
      renderData: renderData,
    );
  }

  factory _PostRenderSegment.footer({
    required int scrollIndex,
    required int postIndex,
    required Post post,
  }) {
    return _PostRenderSegment._(
      type: _PostRenderSegmentType.longFooter,
      scrollIndex: scrollIndex,
      postIndex: postIndex,
      post: post,
    );
  }

  factory _PostRenderSegment.gapBefore({
    required int scrollIndex,
    required int postIndex,
    required Post post,
    required int gapCount,
  }) {
    return _PostRenderSegment._(
      type: _PostRenderSegmentType.gapBefore,
      scrollIndex: scrollIndex,
      postIndex: postIndex,
      post: post,
      gapCount: gapCount,
    );
  }

  factory _PostRenderSegment.gapAfter({
    required int scrollIndex,
    required int postIndex,
    required Post post,
    required int gapCount,
  }) {
    return _PostRenderSegment._(
      type: _PostRenderSegmentType.gapAfter,
      scrollIndex: scrollIndex,
      postIndex: postIndex,
      post: post,
      gapCount: gapCount,
    );
  }
}

/// Gap 指示器 - 显示被隐藏的帖子数量，点击后加载
class _GapIndicator extends StatefulWidget {
  final int count;
  final VoidCallback? onTap;

  const _GapIndicator({required this.count, this.onTap});

  @override
  State<_GapIndicator> createState() => _GapIndicatorState();
}

class _GapIndicatorState extends State<_GapIndicator> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: _loading
          ? null
          : () {
              setState(() => _loading = true);
              widget.onTap?.call();
            },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.3,
          ),
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_loading)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.unfold_more,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              ),
            Text(
              _loading
                  ? S.current.topicDetail_loading
                  : S.current.topicDetail_showHiddenReplies(widget.count),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 加载失败时的重试提示
class _LoadFailedRetry extends StatelessWidget {
  final VoidCallback? onRetry;

  const _LoadFailedRetry({this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: GestureDetector(
          onTap: onRetry,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                S.current.topicDetail_loadFailedTapRetry,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadMoreIndicator extends StatelessWidget {
  const _LoadMoreIndicator();

  @override
  Widget build(BuildContext context) {
    return const TopicLinearLoadingIndicator(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
    );
  }
}

class _IncomingRepliesIndicator extends StatelessWidget {
  const _IncomingRepliesIndicator({required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_downward_rounded,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.topic_newRepliesSinceSummary(count),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
