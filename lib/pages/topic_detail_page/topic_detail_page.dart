import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../services/app_error_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Priority, SchedulerBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:share_plus/share_plus.dart';
import '../../l10n/s.dart';
import '../../utils/html_text_mapper.dart';
import '../../utils/html_to_markdown.dart';
import '../../utils/code_selection_context.dart';
import '../../utils/link_launcher.dart';
import '../../utils/quote_builder.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'dart:ui';
import '../../models/draft.dart';
import '../../models/nested_topic.dart';
import '../../models/topic.dart';
import '../../utils/responsive.dart';
import '../../utils/share_utils.dart';
import '../../providers/preferences_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/home_topic_excerpt_provider.dart';
import '../reading_settings_page.dart';
import '../../providers/selected_topic_provider.dart';
import '../../providers/discourse_providers.dart';
import '../../providers/message_bus_providers.dart';
import '../../providers/pinned_categories_provider.dart';
import '../../services/discourse/discourse_service.dart';
import '../../services/settings/content_filter_service.dart';
import '../../services/notion/notion_bookmark_auto_sync.dart';
import '../../services/screen_track.dart';
import '../../services/topic_reading_state_service.dart';
import '../../services/toast_service.dart';
import '../../services/log/log_writer.dart';
import '../../services/navigation/app_route_observer.dart';
import '../../services/navigation/pop_passthrough_material_page_route.dart';
import '../../widgets/content/lazy_load_scope.dart';
import '../../widgets/post/post_item_skeleton.dart';
import '../../widgets/post/post_item/quote_selection_helper.dart';
import '../../widgets/post/post_replies_sheet.dart';
import '../../widgets/post/reply_sheet.dart';
import '../../widgets/topic/topic_progress.dart';
import '../../widgets/topic/topic_notification_button.dart';
import '../../widgets/common/dismissible_popup_menu.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/content/discourse_html_content/chunked/chunked_html_content.dart';
import '../../widgets/content/discourse_html_content/discourse_html_content_widget.dart';
import '../../providers/nested_topic_provider.dart';
import 'controllers/topic_detail_controller.dart';
import 'widgets/nested_post_list.dart';
import 'widgets/progress_gesture_action_meta.dart';
import 'widgets/topic_detail_overlay.dart';
import 'widgets/topic_post_list.dart';
import 'widgets/topic_detail_header.dart';
import '../../widgets/layout/master_detail_layout.dart';
import '../../widgets/share/share_image_preview.dart';
import '../../widgets/share/export_sheet.dart';
import '../../widgets/bookmark/bookmark_edit_sheet.dart';
import '../../providers/read_later_provider.dart';
import '../../models/read_later_item.dart';
import '../../providers/topic_search_provider.dart';
import '../edit_topic_page.dart';
import 'widgets/ai_chat_page.dart';
import 'widgets/ai_chat_guide.dart';
import '../../utils/dialog_utils.dart';
import '../../utils/platform_utils.dart';
import '../../models/shortcut_binding.dart';
import '../../providers/shortcut_provider.dart';
import '../../widgets/desktop_refresh_indicator.dart';

part 'actions/_scroll_actions.dart';
part 'actions/_user_actions.dart';
part 'actions/_filter_actions.dart';

const double _topicDetailToolbarHeight = 48.0;
const double _topicFloatingButtonSize = 44.0;
const double _topicActionMenuWidth = 128.0;
const double _topicTopContentGap = 3.6;

@visibleForTesting
bool shouldShowTopicTimelineProgress({
  required bool isNestedView,
  required bool isTopLevelMode,
}) {
  return !isNestedView && !isTopLevelMode;
}

@visibleForTesting
bool shouldBlockForFlatJumpTarget({
  required bool isNestedView,
  required int? jumpTargetPostNumber,
  required bool hasLoadedPosts,
  required int? firstLoadedPostNumber,
  required int? lastLoadedPostNumber,
}) {
  final target = jumpTargetPostNumber;
  if (isNestedView || target == null || target <= 0) return false;
  if (!hasLoadedPosts ||
      firstLoadedPostNumber == null ||
      lastLoadedPostNumber == null) {
    return true;
  }
  return target < firstLoadedPostNumber || target > lastLoadedPostNumber;
}

@visibleForTesting
int? resolveInitialPendingNestedPostNumber({
  required bool isNestedView,
  required int? scrollToPostNumber,
  required bool restoredNestedView,
  required int? restoredPostNumber,
  bool hasInitialPreview = false,
}) {
  if (!isNestedView) return null;

  final explicitTarget = _validPostNumber(scrollToPostNumber);
  if (explicitTarget != null) return explicitTarget;

  if (hasInitialPreview) return null;

  if (!restoredNestedView) return null;
  return _validPostNumber(restoredPostNumber);
}

@visibleForTesting
int? resolveInitialFlatPostNumber({
  required bool hasInitialPreview,
  required int? scrollToPostNumber,
  required bool restoredNestedView,
  required int? restoredPostNumber,
}) {
  final explicitTarget = _validPostNumber(scrollToPostNumber);
  if (explicitTarget != null) return explicitTarget;
  if (hasInitialPreview) return null;
  return restoredNestedView ? null : _validPostNumber(restoredPostNumber);
}

@visibleForTesting
bool resolveInitialNestedView({
  required bool? initialNestedView,
  required bool? restoredNestedView,
  required bool preferenceNestedView,
}) {
  if (initialNestedView != null) return initialNestedView;
  return restoredNestedView ?? preferenceNestedView;
}

int? _validPostNumber(int? postNumber) {
  return postNumber != null && postNumber > 0 ? postNumber : null;
}

@visibleForTesting
TopicDetail buildTopicDetailPreviewFromTopic({
  required Topic topic,
  required String previewHtml,
  String? initialTitle,
}) {
  final createdBy = topic.posters.firstOrNull?.user;
  final previewTime = topic.createdAt ?? topic.lastPostedAt ?? DateTime.now();
  final previewPost = Post(
    id: topic.id * 1000000 + 1,
    topicId: topic.id,
    username: createdBy?.username ?? topic.lastPosterUsername ?? '',
    avatarTemplate: createdBy?.avatarTemplate ?? '',
    animatedAvatar: createdBy?.animatedAvatar,
    cooked: previewHtml,
    postNumber: 1,
    postType: 1,
    updatedAt: previewTime,
    createdAt: previewTime,
    likeCount: 0,
    replyCount: topic.replyCount,
    read: true,
    userId: createdBy?.id,
  );

  return TopicDetail(
    id: topic.id,
    title: initialTitle ?? topic.title,
    slug: topic.slug,
    postsCount: topic.postsCount,
    postStream: PostStream(
      posts: [previewPost],
      stream: [previewPost.id],
      gaps: const PostStreamGaps(),
    ),
    categoryId: int.tryParse(topic.categoryId) ?? 0,
    closed: topic.closed,
    archived: topic.archived,
    tags: topic.tags,
    views: topic.views,
    likeCount: topic.likeCount,
    createdAt: topic.createdAt ?? previewTime,
    lastReadPostNumber: topic.lastReadPostNumber,
    createdBy: createdBy,
    bookmarked: topic.bookmarkableType == 'Topic' && topic.bookmarkId != null,
    bookmarkId: topic.bookmarkableType == 'Topic' ? topic.bookmarkId : null,
    bookmarkName: topic.bookmarkableType == 'Topic' ? topic.bookmarkName : null,
    bookmarkReminderAt: topic.bookmarkableType == 'Topic'
        ? topic.bookmarkReminderAt
        : null,
    hasAcceptedAnswer: topic.hasAcceptedAnswer,
  );
}

@visibleForTesting
NestedTopicState? buildInitialNestedPreviewState(TopicDetail detail) {
  final previewPost = detail.postStream.posts.firstOrNull;
  if (previewPost == null || previewPost.postNumber != 1) return null;
  return NestedTopicState(
    topicJson: {'title': detail.title},
    opPost: previewPost,
    roots: const [],
    hasMoreRoots: true,
    isLoadingMore: true,
  );
}

@visibleForTesting
TopicDetail mergeTopicDetailWithInitialPreview({
  required TopicDetail detail,
  required TopicDetail? previewDetail,
}) {
  final previewPosts = previewDetail?.postStream.posts;
  if (previewPosts == null || previewPosts.isEmpty) return detail;

  final previewFirstPost = previewPosts.first;
  if (previewFirstPost.postNumber != 1 || previewFirstPost.cooked.isEmpty) {
    return detail;
  }

  final posts = detail.postStream.posts;
  if (posts.isEmpty || posts.first.postNumber != 1) return detail;

  final mergedPosts = [...posts];
  mergedPosts[0] = posts.first.copyWith(cooked: previewFirstPost.cooked);

  return detail.copyWith(
    postStream: PostStream(
      posts: mergedPosts,
      stream: detail.postStream.stream,
      gaps: detail.postStream.gaps,
    ),
  );
}

/// 话题详情页面
class TopicDetailPage extends ConsumerStatefulWidget {
  final int topicId;
  final String? initialTitle;
  final int? scrollToPostNumber; // 外部控制的跳转位置（如从通知跳转到指定楼层）
  final bool embeddedMode; // 嵌入模式（双栏布局中使用，不显示返回按钮）
  final bool parentActive; // 父容器是否可见（IndexedStack/双栏切 tab 时用）
  final bool autoSwitchToMasterDetail; // 仅在从首页进入时允许自动切换
  final bool autoOpenReply; // 自动打开回复框（从草稿进入时使用）
  final int? autoReplyToPostNumber; // 自动回复的帖子编号（从草稿进入时使用）
  final String? instanceId; // 外部指定的 provider 实例 ID（布局切换时复用）
  final bool autoOpenAiChat; // 自动打开 AI 聊天面板
  final String? initialSessionId; // AI 聊天初始会话 ID
  final String? highlightBoostUsername; // 高亮指定用户的 boost（从 boost 通知跳转时使用）
  final bool? initialNestedView; // 外部链接可指定初始树形/普通视图
  final Topic? initialTopicPreview; // 首页已知的话题摘要数据
  final String? initialFirstPostHtml; // 首页已缓存的主贴 HTML

  const TopicDetailPage({
    super.key,
    required this.topicId,
    this.initialTitle,
    this.scrollToPostNumber,
    this.embeddedMode = false,
    this.parentActive = true,
    this.autoSwitchToMasterDetail = false,
    this.autoOpenReply = false,
    this.autoReplyToPostNumber,
    this.instanceId,
    this.autoOpenAiChat = false,
    this.initialSessionId,
    this.highlightBoostUsername,
    this.initialNestedView,
    this.initialTopicPreview,
    this.initialFirstPostHtml,
  });

  @override
  ConsumerState<TopicDetailPage> createState() => _TopicDetailPageState();
}

class _TopicDetailPageState extends ConsumerState<TopicDetailPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin, RouteAware {
  static const int _topicPage = 0;
  static const int _aiPage = 1;

  /// 唯一实例 ID，确保每次打开页面都创建新的 provider 实例
  /// 支持外部传入以在布局切换时复用同一个 provider
  late final String _instanceId = widget.instanceId ?? const Uuid().v4();

  /// Provider 参数（简化重复创建）
  TopicDetailParams get _params => TopicDetailParams(
    widget.topicId,
    postNumber: _controller.currentPostNumber,
    instanceId: _instanceId,
  );

  // Controller
  late final TopicDetailController _controller;
  late final ScreenTrack _screenTrack;

  // UI State
  final GlobalKey _headerKey = GlobalKey();
  final GlobalKey _centerKey = GlobalKey();
  bool _hasFirstPost = false;
  bool _isCheckTitleVisibilityScheduled = false;
  bool _isRefreshing = false;

  /// 标题是否显示（用 ValueNotifier 隔离 AppBar 更新）
  final ValueNotifier<bool> _showTitleNotifier = ValueNotifier<bool>(false);

  /// AppBar 是否有阴影（用 ValueNotifier 隔离 AppBar 更新）
  final ValueNotifier<bool> _isScrolledUnderNotifier = ValueNotifier<bool>(
    false,
  );

  /// 展开头部是否可见（用 ValueNotifier 隔离 UI 更新）
  final ValueNotifier<bool> _isOverlayVisibleNotifier = ValueNotifier<bool>(
    false,
  );

  /// 页面是否停在最顶部；用于顶部悬浮按钮在标题区域自动隐藏
  final ValueNotifier<bool> _isAtTopNotifier = ValueNotifier<bool>(true);
  bool _isSwitchingMode = false; // 切换热门回复模式
  late bool _isNestedView; // 嵌套视图模式
  bool _isTopicBookmarking = false;
  Map<int, int> _nestedPostNumberToScrollIndex = const {};
  Set<int> _nestedExpandedPostNumbers = const <int>{};
  // 搜索相关
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  int _topicSearchResultIndex = 0;
  late final AnimationController _expandController;
  late final Animation<Offset> _animation;
  Set<int> _lastReadPostNumbers = {};
  bool? _lastCanShowDetailPane;
  bool _isAutoSwitching = false;
  bool _autoOpenReplyHandled = false; // 是否已处理自动打开回复框
  bool _autoOpenAiChatHandled = false; // 是否已处理自动打开 AI 聊天
  late final TopicSearchNotifier _topicSearchNotifier;
  // AI 滑动入口相关
  late final PageController _pageController;
  final ValueNotifier<int> _currentPageNotifier = ValueNotifier<int>(
    _topicPage,
  );
  bool _aiGuideChecked = false;
  // 缓存清理快捷键的回调，避免在 dispose 中使用 ref.read
  VoidCallback? _clearShortcuts;
  ModalRoute<dynamic>? _route;
  bool _isRouteVisible = true;
  bool _isParentActive = true;
  bool _isScreenTrackRunning = false;
  TopicReadingState? _restoredReadingState;
  int? _pendingNestedRestorePostNumber;
  int? _lastPrimedNestedTargetPostNumber;
  int? _lastUnreachableJumpTarget;

  String? get _initialPreviewHtml {
    final firstPostHtml = widget.initialFirstPostHtml?.trim();
    if (firstPostHtml != null && firstPostHtml.isNotEmpty) {
      return firstPostHtml;
    }

    final excerpt = widget.initialTopicPreview?.excerpt?.trim();
    if (excerpt != null && excerpt.isNotEmpty) {
      return excerpt;
    }

    return null;
  }

  bool get _canShowInitialPreview {
    return widget.initialTopicPreview != null && _initialPreviewHtml != null;
  }

  TopicDetail? get _initialPreviewDetail {
    if (!_canShowInitialPreview) return null;

    final cachedPreview = ref
        .read(homeTopicExcerptLoaderProvider)
        .peekCachedPreview(widget.topicId);
    if (cachedPreview != null) {
      return cachedPreview.copyWith(
        title: widget.initialTitle ?? cachedPreview.title,
      );
    }

    final topic = widget.initialTopicPreview;
    final previewHtml = _initialPreviewHtml;
    if (topic == null || previewHtml == null) return null;

    return buildTopicDetailPreviewFromTopic(
      topic: topic,
      previewHtml: previewHtml,
      initialTitle: widget.initialTitle,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _seedTopicDetailPreviewCache();
    _isParentActive = widget.parentActive;
    _restoredReadingState = _canRestoreReadingState
        ? ref.read(topicReadingStateServiceProvider).getState(widget.topicId)
        : null;
    _isNestedView = resolveInitialNestedView(
      initialNestedView: widget.initialNestedView,
      restoredNestedView: _restoredReadingState?.nestedView,
      preferenceNestedView: ref
          .read(preferencesProvider)
          .defaultNestedTopicView,
    );
    _pendingNestedRestorePostNumber = resolveInitialPendingNestedPostNumber(
      isNestedView: _isNestedView,
      scrollToPostNumber: widget.scrollToPostNumber,
      restoredNestedView: _restoredReadingState?.nestedView == true,
      restoredPostNumber: _restoredReadingState?.postNumber,
      hasInitialPreview: _canShowInitialPreview,
    );

    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _animation =
        Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _expandController,
            curve: Curves.easeOutCubic,
          ),
        )..addStatusListener((status) {
          if (status == AnimationStatus.forward) {
            _isOverlayVisibleNotifier.value = true;
          } else if (status == AnimationStatus.dismissed) {
            _isOverlayVisibleNotifier.value = false;
          }
        });

    final trackEnabled = ref.read(currentUserProvider).value != null;
    _topicSearchNotifier = ref.read(
      topicSearchProvider(widget.topicId).notifier,
    );

    _screenTrack = ScreenTrack(
      DiscourseService(),
      debugSourceId: _instanceId,
      onTimingsSent: (topicId, postNumbers, highestSeen) {
        debugPrint(
          '[TopicDetail] onTimingsSent callback triggered: topicId=$topicId, highestSeen=$highestSeen',
        );
        // 更新会话已读状态，触发 PostItem 消除未读圆点
        ref
            .read(topicSessionProvider(topicId).notifier)
            .markAsRead(postNumbers);
        SchedulerBinding.instance.scheduleTask(() {
          if (!mounted) return;
          final pinnedIds = ref.read(pinnedCategoriesProvider);
          final categoryIds = [null, ...pinnedIds];
          for (final categoryId in categoryIds) {
            ref
                .read(topicListProvider(categoryId).notifier)
                .updateSeen(topicId, highestSeen);
          }
        }, Priority.idle);
      },
    );

    _controller = TopicDetailController(
      scrollController: AutoScrollController(),
      screenTrack: _screenTrack,
      trackEnabled: trackEnabled,
      initialPostNumber: resolveInitialFlatPostNumber(
        hasInitialPreview: _canShowInitialPreview,
        scrollToPostNumber: widget.scrollToPostNumber,
        restoredNestedView: _restoredReadingState?.nestedView == true,
        restoredPostNumber: _restoredReadingState?.postNumber,
      ),
      onScrolled: () {
        if (_controller.trackEnabled) {
          _screenTrack.scrolled();
        }
      },
    );
    if (_restoredReadingState != null && widget.scrollToPostNumber == null) {
      _controller.skipNextJumpHighlight = true;
    }

    _controller.scrollController.addListener(_onScroll);
    _pageController = PageController(initialPage: _topicPage);

    // 桌面端：注册 J/K 帖子导航 + AI 面板切换
    if (PlatformUtils.isDesktop) {
      toggleAiPanelNotifier.addListener(_onToggleAiPanel);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _registerPostShortcuts();
      });
    }
  }

  void _seedTopicDetailPreviewCache() {
    final previewDetail = _initialPreviewDetail;
    if (previewDetail == null) return;

    final username = ref.read(currentUserProvider).value?.username;
    final cache = ref.read(topicDetailCacheServiceProvider);
    final existing = cache.read(widget.topicId, username: username);
    final existingPostsCount = existing?.detail.postStream.posts.length ?? 0;
    if (existingPostsCount > 1) return;

    cache.writePreviewSeed(previewDetail, username: username);
  }

  bool _isAiSheetOpen = false;

  bool get _canRestoreReadingState {
    return widget.scrollToPostNumber == null &&
        !widget.autoOpenReply &&
        widget.autoReplyToPostNumber == null &&
        !widget.autoOpenAiChat &&
        widget.initialSessionId == null &&
        widget.highlightBoostUsername == null;
  }

  void _onToggleAiPanel() {
    if (!mounted) return;
    final swipeMode = ref.read(preferencesProvider).aiSwipeEntry;
    if (swipeMode) {
      // 滑动模式：PageView 切换
      final target = _currentPageNotifier.value == _topicPage
          ? _aiPage
          : _topicPage;
      _pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      // 弹窗模式：切换开关
      if (_isAiSheetOpen) {
        Navigator.of(context).pop();
        _isAiSheetOpen = false;
      } else {
        final detail = ref.read(topicDetailProvider(_params)).value;
        if (detail == null) return;
        _isAiSheetOpen = true;
        _showAiAssistantSheet(detail);
      }
    }
  }

  void _animateToTopicPage() {
    _pageController.animateToPage(
      _topicPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _registerPostShortcuts() {
    // 闭包内用 mounted 保护，防止 disposed 后被调用
    final shortcuts = <ShortcutAction, VoidCallback>{
      ShortcutAction.nextItem: () {
        if (mounted) _scrollToNextPost();
      },
      ShortcutAction.previousItem: () {
        if (mounted) _scrollToPreviousPost();
      },
    };
    final notifier = widget.embeddedMode
        ? ref.read(detailShortcutsProvider.notifier)
        : ref.read(contextShortcutsProvider.notifier);
    _clearShortcuts = () => notifier.state = {};
    if (widget.embeddedMode) {
      notifier.state = shortcuts;
    } else {
      notifier.state = {
        ...shortcuts,
        ShortcutAction.closeOverlay: () {
          if (mounted) Navigator.of(context).maybePop();
        },
      };
    }
  }

  @override
  void didUpdateWidget(covariant TopicDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parentActive != widget.parentActive) {
      _isParentActive = widget.parentActive;
      _syncScreenTrackState(
        reason: _isParentActive ? 'parent_active' : 'parent_inactive',
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == _route || route == null) return;

    if (_route != null) {
      appRouteObserver.unsubscribe(this);
    }

    _route = route;
    appRouteObserver.subscribe(this, route);
    _isRouteVisible = route.isCurrent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncScreenTrackState(reason: 'route_subscribed');
    });
  }

  @override
  void dispose() {
    QuoteSelectionHelper.updateSelectionActive(null);
    if (_route != null) {
      appRouteObserver.unsubscribe(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    _expandController.dispose();
    _showTitleNotifier.dispose();
    _isScrolledUnderNotifier.dispose();
    _isOverlayVisibleNotifier.dispose();
    _isAtTopNotifier.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _pageController.dispose();
    _currentPageNotifier.dispose();
    _controller.scrollController.removeListener(_onScroll);
    _screenTrack.stop();
    _controller.dispose();
    if (PlatformUtils.isDesktop) {
      toggleAiPanelNotifier.removeListener(_onToggleAiPanel);
      // 延迟注销快捷键，避免在 widget tree finalizing 期间修改 provider
      final clear = _clearShortcuts;
      if (clear != null) Future(clear);
    }
    // 延迟清理搜索状态，避免在 widget tree finalizing 期间修改 provider
    Future(_topicSearchNotifier.exitSearchMode);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final hasFocus = state == AppLifecycleState.resumed;
    _screenTrack.setHasFocus(hasFocus);
  }

  @override
  void didPush() {
    _setRouteVisible(true, 'did_push');
  }

  @override
  void didPopNext() {
    _setRouteVisible(true, 'did_pop_next');
  }

  @override
  void didPushNext() {
    _setRouteVisible(false, 'did_push_next');
  }

  @override
  void didPop() {
    _setRouteVisible(false, 'did_pop');
  }

  void _setRouteVisible(bool visible, String reason) {
    if (_isRouteVisible == visible) return;
    _isRouteVisible = visible;
    _syncScreenTrackState(reason: reason);
  }

  void _syncScreenTrackState({required String reason}) {
    final shouldRun =
        _controller.trackEnabled && _isRouteVisible && _isParentActive;
    if (shouldRun == _isScreenTrackRunning) return;

    if (shouldRun) {
      _screenTrack.start(widget.topicId);
      // start() 会 reset _onscreen，用 controller 当前已知的可见帖子恢复
      // 避免因 CF 验证等场景 stop→start 后 _onscreen 为空导致无法记录阅读时长
      if (_controller.visiblePostNumbers.isNotEmpty) {
        _screenTrack.setOnscreen(_controller.visiblePostNumbers);
        _screenTrack.scrolled();
      }
    } else {
      _screenTrack.stop();
    }
    _isScreenTrackRunning = shouldRun;

    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'info',
      'type': 'lifecycle',
      'event': 'screen_track_state',
      'message': shouldRun ? 'ScreenTrack 启动' : 'ScreenTrack 停止',
      'topicId': widget.topicId,
      'screenTrackSourceId': _instanceId,
      'routeVisible': _isRouteVisible,
      'parentActive': _isParentActive,
      'reason': reason,
    });
  }

  void _scheduleCheckTitleVisibility() {
    if (_isCheckTitleVisibilityScheduled || !mounted) return;
    _isCheckTitleVisibilityScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isCheckTitleVisibilityScheduled = false;
      if (mounted) {
        _checkTitleVisibility();
      }
    });
  }

  void _checkTitleVisibility() {
    final barHeight =
        _topicDetailToolbarHeight + MediaQuery.of(context).padding.top;
    final ctx = _headerKey.currentContext;

    if (ctx == null) {
      if (_hasFirstPost) {
        _showTitleNotifier.value = true;
      }
      _isScrolledUnderNotifier.value = true;
    } else {
      final box = ctx.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final position = box.localToGlobal(Offset.zero);
        final headerVisible = position.dy >= barHeight;
        _showTitleNotifier.value = !headerVisible;
        _isScrolledUnderNotifier.value = !_hasFirstPost || !headerVisible;
      }
    }
  }

  void _toggleExpandedHeader() {
    if (_expandController.status == AnimationStatus.completed ||
        _expandController.status == AnimationStatus.forward) {
      _expandController.reverse();
    } else {
      _expandController.forward();
    }
  }

  void _maybeSwitchToMasterDetail(bool canShowDetailPane, TopicDetail? detail) {
    if (widget.embeddedMode) {
      _lastCanShowDetailPane = canShowDetailPane;
      return;
    }

    if (!widget.autoSwitchToMasterDetail) {
      _lastCanShowDetailPane = canShowDetailPane;
      return;
    }

    if (_isAutoSwitching) return;

    // 当前页面不在栈顶时（有其他页面覆盖），不更新状态也不触发导航
    // 这样返回后能正确检测到布局变化并执行切换
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    final previous = _lastCanShowDetailPane;
    _lastCanShowDetailPane = canShowDetailPane;

    if (previous == null) {
      if (canShowDetailPane) {
        _switchToMasterDetail(detail);
      }
      return;
    }
    if (previous == canShowDetailPane) return;
    if (!previous && canShowDetailPane) {
      _switchToMasterDetail(detail);
    }
  }

  void _switchToMasterDetail(TopicDetail? detail) {
    _isAutoSwitching = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (!navigator.canPop()) {
        _isAutoSwitching = false;
        return;
      }

      final currentPostNumber =
          _controller.currentPostNumber ?? widget.scrollToPostNumber;
      ref
          .read(selectedTopicProvider.notifier)
          .select(
            topicId: widget.topicId,
            initialTitle: detail?.title ?? widget.initialTitle,
            scrollToPostNumber: currentPostNumber,
            instanceId: _instanceId,
          );
      navigator.pop();
    });
  }

  /// 在大屏上为内容添加宽度约束
  Widget _wrapWithConstraint(Widget child) {
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

  Widget _buildCollapsibleAppBarOverlay({
    required ThemeData theme,
    required TopicDetail? detail,
    required TopicDetailNotifier notifier,
    required bool visible,
  }) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, -1.4),
          duration: topicDetailBarAnimationDuration,
          curve: topicDetailBarAnimationCurve,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: topicDetailBarAnimationDuration,
            curve: topicDetailBarAnimationCurve,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (widget.embeddedMode)
                  const SizedBox(width: _topicFloatingButtonSize)
                else
                  _FloatingTopicChromeButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    icon: Icons.arrow_back_ios_new_rounded,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                if (detail == null)
                  const SizedBox(width: _topicFloatingButtonSize)
                else
                  _buildFloatingTopicMenu(
                    theme: theme,
                    detail: detail,
                    notifier: notifier,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingTopicMenu({
    required ThemeData theme,
    required TopicDetail? detail,
    required TopicDetailNotifier notifier,
  }) {
    if (detail == null) {
      return const SizedBox(width: _topicFloatingButtonSize);
    }

    return SwipeDismissiblePopupMenuButton<String>(
      tooltip: context.l10n.topicDetail_moreOptions,
      offset: const Offset(0, 6),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: _topicActionMenuWidth),
      menuPadding: const EdgeInsets.all(6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: theme.colorScheme.surface.withValues(alpha: 0.98),
      shadowColor: Colors.black.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      child: const _FloatingTopicChromeButtonSurface(icon: Icons.menu_rounded),
      onSelected: (value) => _handleTopicMenuSelection(value, detail, notifier),
      itemBuilder: (context) => _buildTopicMenuItems(detail),
    );
  }

  List<PopupMenuEntry<String>> _buildTopicMenuItems(TopicDetail detail) {
    final firstPost = detail.postStream.posts
        .where((p) => p.postNumber == 1)
        .firstOrNull;
    final canEditTopic = detail.canEdit || (firstPost?.canEdit ?? false);
    final useSwipeEntry = ref.watch(
      preferencesProvider.select((p) => p.aiSwipeEntry),
    );
    final hasAiModel = ref.watch(hasAvailableAiModelProvider);
    final isInReadLater = ref
        .read(readLaterProvider.notifier)
        .contains(widget.topicId);

    PopupMenuItem<String> item({
      required String value,
      required IconData icon,
      required String label,
      bool selected = false,
    }) {
      return PopupMenuItem<String>(
        value: value,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        height: 40,
        child: _TopicMenuTile(icon: icon, label: label, selected: selected),
      );
    }

    return [
      item(
        value: 'search',
        icon: Icons.search_rounded,
        label: context.l10n.common_search,
      ),
      if (!useSwipeEntry && hasAiModel)
        item(
          value: 'ai_assistant',
          icon: Icons.auto_awesome_rounded,
          label: context.l10n.topicDetail_aiAssistant,
        ),
      if (canEditTopic)
        item(
          value: 'edit_topic',
          icon: Icons.edit_outlined,
          label: context.l10n.topicDetail_editTopic,
        ),
      item(
        value: 'read_later',
        icon: isInReadLater ? Icons.layers_rounded : Icons.layers_outlined,
        label: isInReadLater
            ? context.l10n.topicDetail_removeFromReadLater
            : context.l10n.topicDetail_addToReadLater,
        selected: isInReadLater,
      ),
      item(
        value: 'open_in_browser',
        icon: Icons.language_rounded,
        label: context.l10n.topicDetail_openInBrowser,
      ),
      item(
        value: 'subscribe',
        icon: TopicNotificationButton.getIcon(detail.notificationLevel),
        label: context.l10n.topic_notificationSettings,
      ),
      item(
        value: 'toggle_nested_view',
        icon: _isNestedView ? Icons.forum_rounded : Icons.forum_outlined,
        label: context.l10n.nested_title,
        selected: _isNestedView,
      ),
      item(
        value: 'reading_settings',
        icon: Icons.auto_stories_rounded,
        label: context.l10n.settings_reading,
      ),
    ];
  }

  void _handleTopicMenuSelection(
    String value,
    TopicDetail detail,
    TopicDetailNotifier notifier,
  ) {
    if (value == 'search') {
      _showTopicSearch();
    } else if (value == 'ai_assistant') {
      _showAiAssistantSheet(detail);
    } else if (value == 'subscribe') {
      showNotificationLevelSheet(
        context,
        detail.notificationLevel,
        (level) => _handleNotificationLevelChanged(notifier, level),
      );
    } else if (value == 'edit_topic') {
      _handleEditTopic();
    } else if (value == 'read_later') {
      _handleReadLater();
    } else if (value == 'open_in_browser') {
      _openInBrowser();
    } else if (value == 'toggle_nested_view') {
      _setNestedView(!_isNestedView);
    } else if (value == 'reading_settings') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ReadingSettingsPage()),
      );
    }
  }

  void _showTopicSearch() {
    ref.read(topicSearchProvider(widget.topicId).notifier).enterSearchMode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeTopicSearch() {
    _searchController.clear();
    _topicSearchResultIndex = 0;
    ref.read(topicSearchProvider(widget.topicId).notifier).exitSearchMode();
  }

  Future<void> _submitTopicSearch(String query) async {
    final notifier = ref.read(topicSearchProvider(widget.topicId).notifier);
    await notifier.search(query);
    if (!mounted) return;

    final results = ref.read(topicSearchProvider(widget.topicId)).results;
    setState(() => _topicSearchResultIndex = 0);
    if (results.isNotEmpty) {
      await _jumpToTopicSearchResult(0);
    }
  }

  Future<void> _jumpToTopicSearchResult(int index) async {
    final results = ref.read(topicSearchProvider(widget.topicId)).results;
    if (results.isEmpty) return;

    final clampedIndex = index.clamp(0, results.length - 1);
    setState(() => _topicSearchResultIndex = clampedIndex);
    await _scrollToPost(
      results[clampedIndex].postNumber,
      preserveNestedView: _isNestedView,
    );
  }

  void _jumpToPreviousTopicSearchResult() {
    final total = ref.read(topicSearchProvider(widget.topicId)).results.length;
    if (total == 0) return;
    final next = (_topicSearchResultIndex - 1 + total) % total;
    unawaited(_jumpToTopicSearchResult(next));
  }

  void _jumpToNextTopicSearchResult() {
    final total = ref.read(topicSearchProvider(widget.topicId)).results.length;
    if (total == 0) return;
    final next = (_topicSearchResultIndex + 1) % total;
    unawaited(_jumpToTopicSearchResult(next));
  }

  void _showTimelineSheet(TopicDetail detail) {
    final notifier = ref.read(topicDetailProvider(_params).notifier);
    if (!shouldShowTopicTimelineProgress(
      isNestedView: _isNestedView,
      isTopLevelMode: notifier.isTopLevelMode,
    )) {
      return;
    }

    final preserveNestedView = _isNestedView;
    showTopicTimelineSheet(
      context: context,
      currentIndex: _controller.currentVisibleStreamIndex,
      stream: detail.postStream.stream,
      onJumpToStreamIndex: (streamIndex, postId) => _scrollToStreamIndex(
        streamIndex,
        postId,
        preserveNestedView: preserveNestedView,
      ),
      title: detail.title,
    );
  }

  Widget _buildInlineTopicSearchOverlay(TopicSearchState searchState) {
    final theme = Theme.of(context);
    final safeTop = MediaQuery.of(context).padding.top;
    final total = searchState.results.length;
    final current = total == 0 ? 0 : _topicSearchResultIndex + 1;

    return Positioned(
      top: safeTop + 8,
      left: 12,
      right: 12,
      child: Material(
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.16),
        color: theme.colorScheme.surface.withValues(alpha: 0.98),
        surfaceTintColor: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              const SizedBox(width: 6),
              Icon(
                Icons.search_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: context.l10n.topicDetail_searchHint,
                    border: InputBorder.none,
                    isDense: true,
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  style: theme.textTheme.bodyMedium,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (query) => unawaited(_submitTopicSearch(query)),
                ),
              ),
              if (searchState.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '$current/$total',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: total == 0
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              IconButton(
                tooltip: '上一个',
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                onPressed: total > 0 ? _jumpToPreviousTopicSearchResult : null,
              ),
              IconButton(
                tooltip: '下一个',
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                onPressed: total > 0 ? _jumpToNextTopicSearchResult : null,
              ),
              IconButton(
                tooltip: context.l10n.common_close,
                icon: const Icon(Icons.close_rounded),
                onPressed: _closeTopicSearch,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLoggedIn = ref.watch(currentUserProvider).value != null;
    final canShowDetailPane = MasterDetailLayout.canShowBothPanesFor(context);
    // 依赖头像策略开关，确保当前帖子页在偏好切换后重建并刷新头像 URL。
    ref.watch(preferencesProvider.select((p) => p.preferStaticAvatars));

    ref.listen<AsyncValue<void>>(authStateProvider, (_, _) {
      if (!context.mounted) return;
      final stillLoggedIn = ref.read(currentUserProvider).value != null;
      if (_controller.trackEnabled != stillLoggedIn) {
        _controller.trackEnabled = stillLoggedIn;
        _syncScreenTrackState(
          reason: stillLoggedIn ? 'auth_logged_in' : 'auth_logged_out',
        );
      }
    });

    final params = _params;
    final detailAsync = ref.watch(topicDetailProvider(params));
    final rawDetail = detailAsync.value;
    final detail = rawDetail == null
        ? null
        : mergeTopicDetailWithInitialPreview(
            detail: rawDetail,
            previewDetail: _initialPreviewDetail,
          );
    final notifier = ref.read(topicDetailProvider(params).notifier);
    final nestedParams = NestedTopicParams(topicId: widget.topicId);
    final primedNestedAsync = _isNestedView
        ? ref.watch(nestedTopicProvider(nestedParams))
        : null;

    ref.listen<TopicSessionState>(topicSessionProvider(widget.topicId), (
      _,
      next,
    ) {
      final raw = ref.read(topicDetailProvider(params)).value;
      if (raw == null) return;
      final currentDetail = mergeTopicDetailWithInitialPreview(
        detail: raw,
        previewDetail: _initialPreviewDetail,
      );
      _syncReadPostNumbersForDetail(currentDetail, next.readPostNumbers);
    });

    _maybeSwitchToMasterDetail(canShowDetailPane, detail);

    // 监听 MessageBus 事件
    ref.listen(topicChannelProvider(widget.topicId), (previous, next) {
      if (!context.mounted) return;
      // 1. reload_topic（话题状态变更：关闭/打开/固定等）
      if (next.reloadRequested && !(previous?.reloadRequested ?? false)) {
        ref
            .read(topicChannelProvider(widget.topicId).notifier)
            .clearReloadRequest();
        _handleReloadTopic(notifier, next.refreshStreamRequested);
        return;
      }

      // 2. notification_level_change（通知级别变更）
      if (next.notificationLevelChange != null &&
          previous?.notificationLevelChange != next.notificationLevelChange) {
        final level = TopicNotificationLevel.fromValue(
          next.notificationLevelChange!,
        );
        ref
            .read(topicChannelProvider(widget.topicId).notifier)
            .clearNotificationLevelChange();
        notifier.updateNotificationLevelLocally(level);
        return;
      }

      // 3. stats 更新
      if (next.statsUpdate != null &&
          previous?.statsUpdate != next.statsUpdate) {
        notifier.applyStatsUpdate(next.statsUpdate!);
        ref
            .read(topicChannelProvider(widget.topicId).notifier)
            .clearStatsUpdate();
      }

      // 4. shared_issue 计数更新
      if (next.sharedIssueUpdate != null &&
          previous?.sharedIssueUpdate != next.sharedIssueUpdate) {
        notifier.updateSharedIssue(next.sharedIssueUpdate!.count);
        ref
            .read(topicChannelProvider(widget.topicId).notifier)
            .clearSharedIssueUpdate();
      }

      // 5. 帖子级别更新（created/revised/deleted/liked 等）
      final prevLen = previous?.postUpdates.length ?? 0;
      final nextLen = next.postUpdates.length;
      if (nextLen > prevLen) {
        final newUpdates = next.postUpdates.sublist(prevLen);
        for (final update in newUpdates) {
          _handlePostUpdate(notifier, update);
        }
      }
    });

    // 预解析帖子 HTML
    ref.listen(topicDetailProvider(params), (previous, next) {
      if (!context.mounted) return;
      final posts = next.value?.postStream.posts;
      if (posts != null && posts.isNotEmpty) {
        final htmlList = posts.map((p) => p.cooked).toList();
        ChunkedHtmlContent.preloadAll(htmlList);

        // 预热 Pangu 混排处理（在 isolate 中执行）
        if (ref.read(preferencesProvider).displayPanguSpacing) {
          DiscourseHtmlContent.preloadPangu(htmlList);
        }

        final hasFirstPost = posts.first.postNumber == 1;
        if (_hasFirstPost != hasFirstPost) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _hasFirstPost = hasFirstPost);
              _scheduleCheckTitleVisibility();
            }
          });
        }

        // 自动打开回复框（从草稿进入时）
        if (widget.autoOpenReply && !_autoOpenReplyHandled) {
          _autoOpenReplyHandled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              // 如果指定了回复帖子编号，找到对应的帖子
              Post? replyToPost;
              if (widget.autoReplyToPostNumber != null) {
                replyToPost = posts
                    .where((p) => p.postNumber == widget.autoReplyToPostNumber)
                    .firstOrNull;
              }
              _handleReply(replyToPost);
            }
          });
        }

        // 自动打开 AI 聊天面板（从会话历史进入时）
        if (widget.autoOpenAiChat && !_autoOpenAiChatHandled) {
          _autoOpenAiChatHandled = true;
          final topicDetail = next.value!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            // 如果指定了会话 ID，先切换到该会话
            if (widget.initialSessionId != null) {
              ref
                  .read(topicAiChatProvider(widget.topicId).notifier)
                  .switchSession(widget.initialSessionId!);
            }
            final swipeMode = ref.read(preferencesProvider).aiSwipeEntry;
            if (swipeMode) {
              _pageController.animateToPage(
                _aiPage,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
              );
            } else {
              _showAiAssistantSheet(topicDetail);
            }
          });
        }
      }
    });

    final searchState = ref.watch(topicSearchProvider(widget.topicId));
    final isSearchMode = searchState.isSearchMode;
    final hasAiModel = ref.watch(hasAvailableAiModelProvider);
    final useSwipeEntry = ref.watch(
      preferencesProvider.select((p) => p.aiSwipeEntry),
    );

    // 保持 AI 聊天 provider 存活，避免 BottomSheet 关闭后状态丢失
    if (hasAiModel) {
      ref.watch(topicAiChatProvider(widget.topicId));
    }

    // 首次引导检查（仅滑动入口模式）
    if (useSwipeEntry && hasAiModel && !_aiGuideChecked && detail != null) {
      _aiGuideChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final prefs = ref.read(sharedPreferencesProvider);
          AiChatGuide.checkAndShow(prefs);
        }
      });
    }

    final hideBarOnScroll = ref.watch(
      preferencesProvider.select((p) => p.hideBarOnScroll),
    );
    final contentTopInset =
        MediaQuery.of(context).padding.top + _topicTopContentGap;
    final topicBody = _buildBody(
      context,
      detailAsync,
      detail,
      notifier,
      isLoggedIn,
      topContentInset: contentTopInset,
      primedNestedAsync: primedNestedAsync,
    );
    final topicScaffold = Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          topicBody,
          ValueListenableBuilder<bool>(
            valueListenable: _controller.showBottomBarNotifier,
            builder: (context, showBars, _) {
              return ValueListenableBuilder<bool>(
                valueListenable: _isAtTopNotifier,
                builder: (context, isAtTop, _) {
                  final shouldShowAppBar =
                      !isAtTop && (!hideBarOnScroll || showBars);
                  return _buildCollapsibleAppBarOverlay(
                    theme: theme,
                    detail: detail,
                    notifier: notifier,
                    visible: shouldShowAppBar,
                  );
                },
              );
            },
          ),
        ],
      ),
    );

    // 无 AI 模型或非滑动入口模式：普通布局
    if (!hasAiModel || !useSwipeEntry) {
      return LazyLoadScope(
        child: PopScope(
          canPop: !isSearchMode,
          onPopInvokedWithResult: (bool didPop, dynamic result) {
            if (!didPop) {
              _closeTopicSearch();
            }
          },
          child: topicScaffold,
        ),
      );
    }

    // 滑动入口模式：PageView 包裹话题详情和 AI 聊天
    return LazyLoadScope(
      child: ValueListenableBuilder<int>(
        valueListenable: _currentPageNotifier,
        builder: (context, currentPage, _) {
          final isOnAiPage = currentPage == _aiPage;
          return PopScope(
            canPop: !isSearchMode && !isOnAiPage,
            onPopInvokedWithResult: (bool didPop, dynamic result) {
              if (!didPop) {
                if (isOnAiPage) {
                  _animateToTopicPage();
                } else {
                  _closeTopicSearch();
                }
              }
            },
            child: _buildSwipeEntryPageView(
              context: context,
              isSearchMode: isSearchMode,
              detail: detail,
              topicScaffold: topicScaffold,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSwipeEntryPageView({
    required BuildContext context,
    required bool isSearchMode,
    required TopicDetail? detail,
    required Widget topicScaffold,
  }) {
    final horizontalPopGestureActive =
        PopPassthroughMaterialPageRoute.horizontalPopGestureActiveListenableOf(
          context,
        );

    Widget buildPageView(bool lockAiSwipe, bool lockTextSelection) {
      return PageView(
        controller: _pageController,
        physics: isSearchMode || lockAiSwipe || lockTextSelection
            ? const NeverScrollableScrollPhysics()
            : const ClampingScrollPhysics(),
        onPageChanged: (page) {
          _currentPageNotifier.value = page;
          // 离开 AI 页面时取消输入框焦点，防止返回时键盘意外弹出
          if (page != _aiPage) {
            FocusManager.instance.primaryFocus?.unfocus();
          }
        },
        children: [
          _KeepAlivePage(child: topicScaffold),
          _KeepAlivePage(
            child: AiChatPage(
              topicId: widget.topicId,
              detail: detail,
              embedded: true,
              onReplyToTopic: detail == null
                  ? null
                  : (imageMarkdown) {
                      _animateToTopicPage();
                      showReplySheet(
                        context: context,
                        topicId: widget.topicId,
                        categoryId: detail.categoryId,
                        initialContent: '$imageMarkdown\n',
                        isPrivateMessageTopic: detail.isPrivateMessage,
                        isPmWithNonHumanUser: detail.pmWithNonHumanUser,
                      );
                    },
            ),
          ),
        ],
      );
    }

    if (horizontalPopGestureActive == null) {
      return ValueListenableBuilder<bool>(
        valueListenable: QuoteSelectionHelper.selectionActiveListenable,
        builder: (context, isSelectionActive, _) =>
            buildPageView(false, isSelectionActive),
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: QuoteSelectionHelper.selectionActiveListenable,
      builder: (context, isSelectionActive, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: horizontalPopGestureActive,
          builder: (context, isHorizontalPopActive, _) =>
              buildPageView(isHorizontalPopActive, isSelectionActive),
        );
      },
    );
  }

  void _showAiAssistantSheet(TopicDetail detail) {
    // 在 modal 外部获取状态栏高度，因为 showModalBottomSheet 会清零 padding.top
    final topPadding = MediaQuery.of(context).padding.top;
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => AiChatPage(
        topicId: widget.topicId,
        detail: detail,
        topPadding: topPadding,
        onReplyToTopic: (imageMarkdown) {
          // 关闭 AI Sheet（预览页已在内部自行关闭）
          Navigator.pop(sheetContext);
          // 打开回复框，预填上传后的图片 markdown
          showReplySheet(
            context: context,
            topicId: widget.topicId,
            categoryId: detail.categoryId,
            initialContent: '$imageMarkdown\n',
            isPrivateMessageTopic: detail.isPrivateMessage,
            isPmWithNonHumanUser: detail.pmWithNonHumanUser,
          );
        },
      ),
    ).then((_) => _isAiSheetOpen = false);
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<TopicDetail> detailAsync,
    TopicDetail? detail,
    TopicDetailNotifier notifier,
    bool isLoggedIn, {
    double topContentInset = 0,
    AsyncValue<NestedTopicState>? primedNestedAsync,
  }) {
    final params = _params;
    final searchState = ref.watch(topicSearchProvider(widget.topicId));
    final isSearchMode = searchState.isSearchMode;
    final searchQuery = isSearchMode ? searchState.query.trim() : '';
    final reduceLoadingAnimations = ref.watch(
      preferencesProvider.select((p) => p.reduceLoadingAnimations),
    );
    final previewDetail = _initialPreviewDetail;
    // 初始加载或切换模式时显示骨架屏
    // 注意：当 hasError 为 true 时，即使 isLoading 也为 true（AsyncLoading.copyWithPrevious 语义），
    // 也应该优先显示错误页面而不是骨架屏
    if (_isSwitchingMode) {
      final showHeaderSkeleton =
          widget.scrollToPostNumber == null || widget.scrollToPostNumber == 0;
      return _wrapWithConstraint(
        PostListSkeleton(
          withHeader: showHeaderSkeleton,
          animate: !reduceLoadingAnimations,
        ),
      );
    }

    if (detailAsync.isLoading && detail == null) {
      if (previewDetail != null) {
        return _buildBodyWithDetail(
          context,
          previewDetail,
          notifier,
          isLoggedIn,
          topContentInset: topContentInset,
          searchHighlightQuery: searchQuery,
          forceFlatView: true,
          forceLoadMoreIndicator: true,
          showTopicOverlay: false,
        );
      }

      final showHeaderSkeleton =
          widget.scrollToPostNumber == null || widget.scrollToPostNumber == 0;
      return _wrapWithConstraint(
        PostListSkeleton(
          withHeader: showHeaderSkeleton,
          animate: !reduceLoadingAnimations,
        ),
      );
    }

    // 跳转中：等待包含目标帖子的新数据 - 显示骨架屏
    final jumpTarget = _controller.jumpTargetPostNumber;
    if (jumpTarget != null && detail != null) {
      final posts = detail.postStream.posts;
      final shouldBlock = shouldBlockForFlatJumpTarget(
        isNestedView: _isNestedView,
        jumpTargetPostNumber: jumpTarget,
        hasLoadedPosts: posts.isNotEmpty,
        firstLoadedPostNumber: posts.isEmpty ? null : posts.first.postNumber,
        lastLoadedPostNumber: posts.isEmpty ? null : posts.last.postNumber,
      );
      if (shouldBlock) {
        if (notifier.isUsingPreviewSeed) {
          return _buildBodyWithDetail(
            context,
            detail,
            notifier,
            isLoggedIn,
            topContentInset: topContentInset,
            searchHighlightQuery: searchQuery,
            forceFlatView: true,
            forceLoadMoreIndicator: true,
            showTopicOverlay: false,
          );
        }
        if (!detailAsync.isLoading) {
          _scheduleUnreachableJumpFallback(jumpTarget);
        }
        return _wrapWithConstraint(
          PostListSkeleton(
            withHeader: false,
            animate: !reduceLoadingAnimations,
          ),
        );
      }
    }

    if (detailAsync.hasError && detail == null) {
      // 错误页面
      return Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverErrorView(
                error: detailAsync.error!,
                onRetry: () => ref.refresh(topicDetailProvider(params)),
              ),
            ],
          ),
          if (isSearchMode) _buildInlineTopicSearchOverlay(searchState),
        ],
      );
    }

    if (detail == null) return const SizedBox();

    return _buildBodyWithDetail(
      context,
      detail,
      notifier,
      isLoggedIn,
      topContentInset: topContentInset,
      searchHighlightQuery: searchQuery,
      primedNestedAsync: primedNestedAsync,
    );
  }

  Widget _buildBodyWithDetail(
    BuildContext context,
    TopicDetail detail,
    TopicDetailNotifier notifier,
    bool isLoggedIn, {
    double topContentInset = 0,
    String? searchHighlightQuery,
    AsyncValue<NestedTopicState>? primedNestedAsync,
    bool forceFlatView = false,
    bool forceLoadMoreIndicator = false,
    bool showTopicOverlay = true,
  }) {
    final searchState = ref.watch(topicSearchProvider(widget.topicId));
    final isSearchMode = searchState.isSearchMode;
    if (_isNestedView &&
        !forceFlatView &&
        _pendingNestedRestorePostNumber != null) {
      _maybePrimeNestedTargetAncestors(detail);
    }
    final content = _buildPostListContent(
      context,
      detail,
      notifier,
      isLoggedIn,
      topContentInset: topContentInset,
      searchHighlightQuery: searchHighlightQuery,
      primedNestedAsync: primedNestedAsync,
      forceFlatView: forceFlatView,
      forceLoadMoreIndicator: forceLoadMoreIndicator,
    );

    // Stack 组装
    return Stack(
      children: [
        content,
        if (isSearchMode) _buildInlineTopicSearchOverlay(searchState),

        // TopicDetailOverlay (Bottom Bar)
        // 使用 ValueListenableBuilder 隔离状态变化，避免整页重建
        if (showTopicOverlay && !isSearchMode)
          ValueListenableBuilder<bool>(
            valueListenable: _controller.showBottomBarNotifier,
            builder: (context, showBottomBar, _) {
              final effectiveShowBottomBar =
                  !ref.watch(
                    preferencesProvider.select((p) => p.hideBarOnScroll),
                  ) ||
                  showBottomBar;
              return ValueListenableBuilder<int>(
                valueListenable: _controller.streamIndexNotifier,
                builder: (context, currentStreamIndex, _) {
                  return TopicDetailOverlay(
                    showBottomBar: effectiveShowBottomBar,
                    isLoggedIn: isLoggedIn,
                    currentStreamIndex: currentStreamIndex,
                    totalCount: detail.postStream.stream.length,
                    detail: detail,
                    onScrollToTop: _scrollToTop,
                    onShare: _shareTopic,
                    onShareAsImage: _shareAsImage,
                    onExport: _showExportSheet,
                    onBookmark: () => _quickAddTopicBookmark(notifier),
                    onBookmarkLongPress: () => _handleBookmarkOptions(notifier),
                    onReply: () => _handleReply(null),
                    onProgressTap: () => _showTimelineSheet(detail),
                    onProgressAction: (action) =>
                        _handleProgressGestureAction(action, detail, notifier),
                    showProgress: shouldShowTopicTimelineProgress(
                      isNestedView: _isNestedView,
                      isTopLevelMode: notifier.isTopLevelMode,
                    ),
                    isSummaryMode: notifier.isSummaryMode,
                    isAuthorOnlyMode: notifier.isAuthorOnlyMode,
                    isTopLevelMode: notifier.isTopLevelMode,
                    isLoading: _isSwitchingMode,
                    onShowTopReplies: _handleShowTopReplies,
                    onShowAuthorOnly: _handleShowAuthorOnly,
                    onShowTopLevelReplies: _handleShowTopLevelReplies,
                    onCancelFilter: _handleCancelFilter,
                  );
                },
              );
            },
          ),

        // Expanded Header 相关组件（使用 ValueListenableBuilder 隔离状态变化）
        if (!isSearchMode)
          ValueListenableBuilder<bool>(
            valueListenable: _isOverlayVisibleNotifier,
            builder: (context, isOverlayVisible, _) {
              if (!isOverlayVisible) return const SizedBox.shrink();

              return Stack(
                children: [
                  // Expanded Header Barrier
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: _toggleExpandedHeader,
                      child: FadeTransition(
                        opacity: _expandController,
                        child: Container(color: Colors.black54),
                      ),
                    ),
                  ),

                  // Expanded Header
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SlideTransition(
                      position: _animation,
                      child: Container(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.7,
                        ),
                        child: Material(
                          color: Theme.of(context).colorScheme.surface,
                          elevation: 0,
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(16),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: SingleChildScrollView(
                            child: TopicDetailHeader(
                              detail: detail,
                              headerKey: null,
                              onVoteChanged: _handleVoteChanged,
                              onNotificationLevelChanged: (level) =>
                                  _handleNotificationLevelChanged(
                                    notifier,
                                    level,
                                  ),
                              onJumpToPost: _scrollToPost,
                              onContinueAiSummary: _continueAiSummary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _buildPostListContent(
    BuildContext context,
    TopicDetail detail,
    TopicDetailNotifier notifier,
    bool isLoggedIn, {
    double topContentInset = 0,
    String? searchHighlightQuery,
    AsyncValue<NestedTopicState>? primedNestedAsync,
    bool forceFlatView = false,
    bool forceLoadMoreIndicator = false,
  }) {
    final posts = detail.postStream.posts;
    final hasFirstPost = posts.isNotEmpty && posts.first.postNumber == 1;
    final sessionState = ref.read(topicSessionProvider(widget.topicId));
    _syncReadPostNumbersForDetail(detail, sessionState.readPostNumbers);

    // 计算分割线位置（热门回复模式下不显示）
    int? dividerPostIndex;
    if (!notifier.isSummaryMode) {
      final lastRead = detail.lastReadPostNumber;
      final totalPosts = detail.postsCount;
      if (lastRead != null && lastRead > 3 && (totalPosts - lastRead) > 1) {
        for (int i = 0; i < posts.length; i++) {
          if (posts[i].postNumber > lastRead) {
            dividerPostIndex = i;
            break;
          }
        }
      }
    }

    // 初始定位
    if (!_controller.hasInitialScrolled && posts.isNotEmpty) {
      _controller.markInitialScrolled(posts.first.postNumber);
      if (_controller.currentPostNumber == null ||
          _controller.currentPostNumber == 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_controller.isPositioned) {
            _controller.markPositioned();
          }
        });
      } else {
        _scrollToInitialPosition(posts, dividerPostIndex);
      }
    }

    final centerPostIndex = _controller.findCenterPostIndex(posts);
    final reduceLoadingAnimations = ref.watch(
      preferencesProvider.select((p) => p.reduceLoadingAnimations),
    );
    final blockedUsernames = ref.watch(
      contentFilterProvider.select((state) => state.normalizedBlockedUsers),
    );

    // 嵌套视图模式
    if (_isNestedView && !forceFlatView) {
      final nestedParams = NestedTopicParams(topicId: widget.topicId);
      final AsyncValue<NestedTopicState> nestedAsync =
          primedNestedAsync ?? ref.watch(nestedTopicProvider(nestedParams));
      Widget buildNestedView(NestedTopicState nestedState) => NestedPostList(
        nestedState: nestedState,
        params: nestedParams,
        detail: detail,
        blockedUsernames: blockedUsernames,
        topicId: widget.topicId,
        scrollController: _controller.scrollController,
        headerKey: _headerKey,
        topContentInset: topContentInset,
        topBoundaryHeight: _topicDetailToolbarHeight,
        isLoggedIn: isLoggedIn,
        onReply: _handleReply,
        onReplyWithInitialContent: (replyToPost, initialContent) =>
            _handleReply(replyToPost, initialContent: initialContent),
        onEdit: _handleEdit,
        onRefreshPost: _handleRefreshPost,
        onJumpToPost: (postNumber) =>
            _scrollToPost(postNumber, preserveNestedView: true),
        onVoteChanged: _handleVoteChanged,
        onSharedIssueChanged: _handleSharedIssueChanged,
        onNotificationLevelChanged: (level) =>
            _handleNotificationLevelChanged(notifier, level),
        onSolutionChanged: _handleSolutionChanged,
        onScrollNotification: _controller.handleScrollNotification,
        onPointerScroll: _controller.handlePointerScroll,
        onPostNumberScrollIndexMappingChanged: (mapping) {
          _nestedPostNumberToScrollIndex = mapping;
          final pendingPostNumber = _pendingNestedRestorePostNumber;
          final scrollIndex = pendingPostNumber == null
              ? null
              : mapping[pendingPostNumber];
          if (pendingPostNumber != null && scrollIndex != null) {
            _pendingNestedRestorePostNumber = null;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              unawaited(
                _controller.scrollController.scrollToIndex(
                  scrollIndex,
                  preferPosition: AutoScrollPosition.middle,
                  duration: const Duration(milliseconds: 1),
                ),
              );
              _controller.updateCurrentPostNumber(pendingPostNumber);
              _controller.clearJumpTarget();
              if (!_controller.isPositioned) {
                _controller.markPositioned();
              }
              if (!_controller.skipNextJumpHighlight) {
                _controller.triggerHighlight(pendingPostNumber);
              }
              _controller.skipNextJumpHighlight = false;
              ref
                      .read(detailScrollPositionProvider(widget.topicId).notifier)
                      .state =
                  pendingPostNumber;
            });
          } else if (pendingPostNumber != null && nestedState.hasMoreRoots) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final latest = ref.read(nestedTopicProvider(nestedParams)).value;
              if (latest == null ||
                  !latest.hasMoreRoots ||
                  latest.isLoadingMore) {
                return;
              }
              unawaited(
                ref.read(nestedTopicProvider(nestedParams).notifier).loadMoreRoots(),
              );
            });
          } else if (pendingPostNumber != null &&
              !nestedState.hasMoreRoots &&
              !nestedState.isLoadingMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _pendingNestedRestorePostNumber = null;
              _controller.clearJumpTarget();
              if (!_controller.isPositioned) {
                _controller.markPositioned();
              }
              if (!_controller.skipNextJumpHighlight) {
                _controller.triggerHighlight(pendingPostNumber);
              }
              _controller.skipNextJumpHighlight = false;
            });
          }
        },
        onContinueAiSummary: _continueAiSummary,
        onFirstVisiblePostChanged: _updateStreamIndexForPostNumber,
        onVisiblePostsChanged: _updateVisiblePosts,
        expandedPostNumbers: _nestedExpandedPostNumbers,
        searchHighlightQuery: searchHighlightQuery,
      );

      Widget nestedView = nestedAsync.when(
        loading: () {
          final previewNestedState = buildInitialNestedPreviewState(detail);
          if (previewNestedState != null) {
            return buildNestedView(previewNestedState);
          }
          return PostListSkeleton(
            withHeader: true,
            animate: !reduceLoadingAnimations,
          );
        },
        error: (e, s) => Center(child: Text('$e')),
        data: buildNestedView,
      );

      return _wrapWithConstraint(nestedView);
    }

    Widget scrollView = ValueListenableBuilder<int?>(
      valueListenable: _controller.highlightNotifier,
      builder: (context, highlightPostNumber, _) {
        return TopicPostList(
          detail: detail,
          blockedUsernames: blockedUsernames,
          scrollController: _controller.scrollController,
          centerKey: _centerKey,
          headerKey: _headerKey,
          topContentInset: topContentInset,
          topBoundaryHeight: _topicDetailToolbarHeight,
          highlightPostNumber: highlightPostNumber,
          highlightBoostUsername: widget.highlightBoostUsername,
          searchHighlightQuery: searchHighlightQuery,
          isLoggedIn: isLoggedIn,
          hasMoreBefore: notifier.hasMoreBefore,
          hasMoreAfter: notifier.hasMoreAfter || forceLoadMoreIndicator,
          isLoadingPrevious: notifier.isLoadingPrevious,
          isLoadingMore: notifier.isLoadingMore || forceLoadMoreIndicator,
          isLoadMoreFailed: notifier.isLoadMoreFailed,
          isLoadPreviousFailed: notifier.isLoadPreviousFailed,
          onRetryLoadMore: () => notifier.retryLoadMore(),
          onRetryLoadPrevious: () => notifier.retryLoadPrevious(),
          centerPostIndex: centerPostIndex,
          dividerPostIndex: dividerPostIndex,
          onFirstVisiblePostChanged: _updateStreamIndexForPostNumber,
          onVisiblePostsChanged: _updateVisiblePosts,
          onScrollIndexMappingChanged: _controller.updateScrollIndexMapping,
          onJumpToPost: _scrollToPost,
          onReply: _handleReply,
          onReplyWithInitialContent: (replyToPost, initialContent) =>
              _handleReply(replyToPost, initialContent: initialContent),
          onEdit: _handleEdit,
          onShareAsImage: _sharePostAsImage,
          onRefreshPost: _handleRefreshPost,
          onVoteChanged: _handleVoteChanged,
          onSharedIssueChanged: _handleSharedIssueChanged,
          onNotificationLevelChanged: (level) =>
              _handleNotificationLevelChanged(notifier, level),
          onSolutionChanged: _handleSolutionChanged,
          onContinueAiSummary: _continueAiSummary,
          onQuoteSelection: isLoggedIn ? _handleQuoteSelection : null,
          onQuoteImage: isLoggedIn ? _handleImageQuote : null,
          onScrollNotification: _controller.handleScrollNotification,
          onPointerScroll: _controller.handlePointerScroll,
          onFillGapBefore: (postId) => notifier.fillGapBefore(postId),
          onFillGapAfter: (postId) => notifier.fillGapAfter(postId),
          onExpandHiddenPost: (postId) => notifier.expandHiddenPost(postId),
          useReplyDialog: notifier.isTopLevelMode,
          onShowPostDetail: (post) => showPostRepliesSheet(
            context: context,
            post: post,
            topicId: widget.topicId,
            onJumpToPost: _scrollToPost,
          ),
        );
      },
    );

    scrollView = DesktopRefreshIndicator(
      refreshNotifier: widget.embeddedMode
          ? detailRefreshNotifier
          : desktopRefreshNotifier,
      onRefresh: _handleRefresh,
      notificationPredicate: (notification) {
        if (!hasFirstPost) return false;
        if (notification.depth != 0) return false;
        return true;
      },
      child: scrollView,
    );

    // 使用 ValueListenableBuilder 隔离定位状态变化，避免整页重建
    // 使用 child 参数避免 scrollView 重建
    return ValueListenableBuilder<bool>(
      valueListenable: _controller.isPositionedNotifier,
      builder: (context, isPositioned, child) {
        final isWaitingForInitialJump =
            !isPositioned &&
            _controller.jumpTargetPostNumber != null &&
            !_canShowInitialPreview;
        if (isWaitingForInitialJump) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Opacity(opacity: 0.0, child: child),
              IgnorePointer(
                child: PostListSkeleton(
                  withHeader: false,
                  animate: !reduceLoadingAnimations,
                ),
              ),
            ],
          );
        }
        return Opacity(
          opacity: isPositioned || _canShowInitialPreview ? 1.0 : 0.0,
          child: child,
        );
      },
      child: scrollView,
    );
  }

  void _syncReadPostNumbersForDetail(
    TopicDetail detail,
    Set<int> sessionReadPostNumbers,
  ) {
    final posts = detail.postStream.posts;
    if (posts.isEmpty) return;
    final readPostNumbers = <int>{};
    for (final post in posts) {
      if (post.read) {
        readPostNumbers.add(post.postNumber);
      }
    }
    readPostNumbers.addAll(sessionReadPostNumbers);
    _updateReadPostNumbers(readPostNumbers);
  }

  void _scheduleUnreachableJumpFallback(int postNumber) {
    if (_lastUnreachableJumpTarget == postNumber) return;
    _lastUnreachableJumpTarget = postNumber;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lastUnreachableJumpTarget = null;
      if (!mounted || _controller.jumpTargetPostNumber != postNumber) return;
      _controller.clearJumpTarget();
      _controller.skipNextJumpHighlight = false;
      if (!_controller.isPositioned) {
        _controller.markPositioned();
      }
      setState(() {});
    });
  }

  void _maybePrimeNestedTargetAncestors(TopicDetail detail) {
    final targetPostNumber = _pendingNestedRestorePostNumber;
    if (targetPostNumber == null ||
        targetPostNumber == _lastPrimedNestedTargetPostNumber) {
      return;
    }
    _lastPrimedNestedTargetPostNumber = targetPostNumber;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_isNestedView ||
          _pendingNestedRestorePostNumber != targetPostNumber) {
        return;
      }
      unawaited(_expandNestedTargetAncestors(detail, targetPostNumber));
    });
  }

  Future<void> _expandNestedTargetAncestors(
    TopicDetail detail,
    int targetPostNumber,
  ) async {
    final loadedPostsByNumber = <int, Post>{
      for (final post in detail.postStream.posts) post.postNumber: post,
    };
    final ancestors = <int>{};
    final seen = <int>{};
    final service = DiscourseService();

    var currentPostNumber = targetPostNumber;
    while (currentPostNumber > 0 && seen.add(currentPostNumber)) {
      Post? post = loadedPostsByNumber[currentPostNumber];
      if (post == null) {
        try {
          post = await service.getPostByNumber(
            widget.topicId,
            currentPostNumber,
          );
        } catch (_) {
          break;
        }
      }

      final parentPostNumber = post.replyToPostNumber;
      if (parentPostNumber <= 1) break;
      ancestors.add(parentPostNumber);
      currentPostNumber = parentPostNumber;
    }

    if (!mounted ||
        !_isNestedView ||
        _pendingNestedRestorePostNumber != targetPostNumber ||
        ancestors.isEmpty ||
        ancestors.difference(_nestedExpandedPostNumbers).isEmpty) {
      return;
    }

    setState(() {
      _nestedExpandedPostNumbers = {
        ..._nestedExpandedPostNumbers,
        ...ancestors,
      };
    });
  }
}

class _FloatingTopicChromeButton extends StatelessWidget {
  const _FloatingTopicChromeButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: _FloatingTopicChromeButtonSurface(icon: icon),
      ),
    );
  }
}

class _FloatingTopicChromeButtonSurface extends StatelessWidget {
  const _FloatingTopicChromeButtonSurface({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: SizedBox(
            width: _topicFloatingButtonSize,
            height: _topicFloatingButtonSize,
            child: Center(child: _FloatingTopicChromeButtonContent(icon: icon)),
          ),
        ),
      ),
    );
  }
}

class _FloatingTopicChromeButtonContent extends StatelessWidget {
  const _FloatingTopicChromeButtonContent({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurface);
  }
}

class _TopicMenuTile extends StatelessWidget {
  const _TopicMenuTile({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconColor = selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primaryContainer.withValues(alpha: 0.72)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.18)
              : colorScheme.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17, color: iconColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: iconColor,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 保持 PageView 子页面存活，防止离屏时 state 被销毁导致滚动位置丢失
class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
