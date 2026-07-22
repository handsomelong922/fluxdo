import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart'
    show ValueNotifier, setEquals, visibleForTesting;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import '../../../l10n/s.dart';
import '../../../models/topic.dart';
import '../../../providers/nested_topic_provider.dart';
import '../../../utils/blocked_user_filter.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/nested/nested_post_card.dart';
import '../../../widgets/post/post_item/post_item.dart';
import 'nested_load_more_trigger.dart';
import 'topic_detail_header.dart';
import 'topic_linear_loading_indicator.dart';

@visibleForTesting
class NestedScrollIndexRegistry {
  final Map<int, int> _postNumberToIndex = <int, int>{};
  final Map<int, int> _indexToPostNumber = <int, int>{};
  int _nextIndex = 0;

  int indexFor(int postNumber) {
    final existing = _postNumberToIndex[postNumber];
    if (existing != null) return existing;

    final index = _nextIndex++;
    _postNumberToIndex[postNumber] = index;
    _indexToPostNumber[index] = postNumber;
    return index;
  }

  int? postNumberFor(int index) => _indexToPostNumber[index];

  Map<int, int> snapshot() => Map<int, int>.from(_postNumberToIndex);

  void reset() {
    _postNumberToIndex.clear();
    _indexToPostNumber.clear();
    _nextIndex = 0;
  }
}

/// 嵌套视图帖子列表 — 在现有 TopicDetailPage 内替换平铺帖子流
class NestedPostList extends ConsumerStatefulWidget {
  final NestedTopicState nestedState;
  final NestedTopicParams params;
  final TopicDetail detail;
  final Set<String> blockedUsernames;
  final int topicId;
  final AutoScrollController scrollController;
  final GlobalKey headerKey;
  final double topContentInset;
  final double topBoundaryHeight;
  final bool isLoggedIn;
  final void Function(Post? replyToPost) onReply;
  final void Function(Post? replyToPost, String initialContent)?
  onReplyWithInitialContent;
  final void Function(Post post) onEdit;
  final void Function(int postId) onRefreshPost;
  final void Function(int postNumber) onJumpToPost;
  final void Function(int, bool) onVoteChanged;
  final void Function(int, bool) onSharedIssueChanged;
  final void Function(TopicNotificationLevel)? onNotificationLevelChanged;
  final void Function(int postId, bool accepted)? onSolutionChanged;
  final bool Function(ScrollNotification) onScrollNotification;
  final ValueChanged<double>? onPointerScroll;
  final void Function(Map<int, int>)? onPostNumberScrollIndexMappingChanged;
  final void Function(TopicSummary summary)? onContinueAiSummary;
  final Set<int> expandedPostNumbers;
  final String? searchHighlightQuery;

  /// 可见帖子上报（走 ScreenTrack 上报链路）
  final void Function(Set<int> visiblePostNumbers)? onVisiblePostsChanged;
  final ValueChanged<int>? onFirstVisiblePostChanged;

  const NestedPostList({
    super.key,
    required this.nestedState,
    required this.params,
    required this.detail,
    required this.blockedUsernames,
    required this.topicId,
    required this.scrollController,
    required this.headerKey,
    this.topContentInset = 0,
    this.topBoundaryHeight = kToolbarHeight,
    required this.isLoggedIn,
    required this.onReply,
    this.onReplyWithInitialContent,
    required this.onEdit,
    required this.onRefreshPost,
    required this.onJumpToPost,
    required this.onVoteChanged,
    required this.onSharedIssueChanged,
    this.onNotificationLevelChanged,
    this.onSolutionChanged,
    required this.onScrollNotification,
    this.onPointerScroll,
    this.onPostNumberScrollIndexMappingChanged,
    this.onContinueAiSummary,
    this.onVisiblePostsChanged,
    this.onFirstVisiblePostChanged,
    this.expandedPostNumbers = const <int>{},
    this.searchHighlightQuery,
  });

  @override
  ConsumerState<NestedPostList> createState() => _NestedPostListState();
}

class _NestedPostListState extends ConsumerState<NestedPostList> {
  static const Duration _visiblePostUpdateDelayDesktop = Duration(
    milliseconds: 240,
  );
  static const Duration _visiblePostUpdateDelayMobile = Duration(
    milliseconds: 360,
  );
  static const Duration _autoChildLoadResumeDelayDesktop = Duration(
    milliseconds: 220,
  );
  static const Duration _autoChildLoadResumeDelayMobile = Duration(
    milliseconds: 320,
  );
  static const int _maxNestedRepliesCacheEntriesMobile = 40;
  static const int _maxNestedRepliesCacheEntriesDesktop = 120;
  final Map<int, bool> _expansionState = {};
  final LinkedHashMap<int, NestedRepliesState> _repliesStateByPostNumber =
      LinkedHashMap<int, NestedRepliesState>();
  final NestedScrollIndexRegistry _scrollIndexRegistry =
      NestedScrollIndexRegistry();
  final NestedLoadMoreTrigger _loadMoreTrigger = NestedLoadMoreTrigger();
  final ValueNotifier<bool> _autoLoadChildrenPausedNotifier =
      ValueNotifier<bool>(false);
  final ValueNotifier<Set<int>> _visiblePostNumbersNotifier =
      ValueNotifier<Set<int>>(const <int>{});
  Timer? _visibilityUpdateTimer;
  Timer? _autoChildLoadResumeTimer;
  bool _visiblePostLayoutUpdateScheduled = false;
  bool _scrollIndexMappingUpdateScheduled = false;
  int? _lastReportedPostNumber;
  Set<int> _lastVisiblePostNumbers = const <int>{};

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateVisiblePostsFromViewport();
      }
    });
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    _visibilityUpdateTimer?.cancel();
    _autoChildLoadResumeTimer?.cancel();
    _autoLoadChildrenPausedNotifier.dispose();
    _visiblePostNumbersNotifier.dispose();
    super.dispose();
  }

  void _onScroll() {
    _scheduleVisiblePostsUpdate();

    if (!widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;

    final ns = widget.nestedState;
    final shouldLoadMore = _loadMoreTrigger.update(
      pixels: position.pixels,
      maxScrollExtent: position.maxScrollExtent,
      hasMoreRoots: ns.hasMoreRoots,
      isLoadingMore: ns.isLoadingMore,
    );
    if (shouldLoadMore) {
      ref.read(nestedTopicProvider(widget.params).notifier).loadMoreRoots();
    }
  }

  @override
  void didUpdateWidget(covariant NestedPostList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.params != widget.params ||
        oldWidget.nestedState.sort != widget.nestedState.sort) {
      _expansionState.clear();
      _repliesStateByPostNumber.clear();
      _loadMoreTrigger.reset();
      _lastVisiblePostNumbers = const <int>{};
      _visiblePostNumbersNotifier.value = const <int>{};
    }
    if (widget.expandedPostNumbers.isNotEmpty &&
        oldWidget.expandedPostNumbers != widget.expandedPostNumbers) {
      for (final postNumber in widget.expandedPostNumbers) {
        _expansionState[postNumber] = true;
        final repliesState = _repliesStateByPostNumber[postNumber];
        if (repliesState != null) {
          _repliesStateByPostNumber[postNumber] = NestedRepliesState(
            children: repliesState.children,
            hasMore: repliesState.hasMore,
            page: repliesState.page,
            expanded: true,
            collapsed: false,
            childrenMaterialized: true,
          );
        }
      }
    }
  }

  int _nextIndexForPost(int postNumber) {
    final index = _scrollIndexRegistry.indexFor(postNumber);
    _scheduleScrollIndexMappingUpdate();
    return index;
  }

  void _scheduleScrollIndexMappingUpdate() {
    if (_scrollIndexMappingUpdateScheduled ||
        widget.onPostNumberScrollIndexMappingChanged == null) {
      return;
    }
    _scrollIndexMappingUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollIndexMappingUpdateScheduled = false;
      if (!mounted) return;
      widget.onPostNumberScrollIndexMappingChanged?.call(
        _scrollIndexRegistry.snapshot(),
      );
    });
  }

  void _scheduleVisiblePostsUpdateAfterLayout() {
    if (_visiblePostLayoutUpdateScheduled) return;
    _visiblePostLayoutUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visiblePostLayoutUpdateScheduled = false;
      if (!mounted) return;
      _updateVisiblePostsFromViewport();
    });
  }

  void _scheduleVisiblePostsUpdate({bool immediate = false}) {
    if (immediate) {
      _visibilityUpdateTimer?.cancel();
      _visibilityUpdateTimer = null;
      if (mounted) {
        _updateVisiblePostsFromViewport();
      }
      return;
    }

    _visibilityUpdateTimer?.cancel();
    _visibilityUpdateTimer = Timer(_visiblePostUpdateDelay, () {
      _visibilityUpdateTimer = null;
      if (!mounted) return;
      _updateVisiblePostsFromViewport();
    });
  }

  void _updateVisiblePostsFromViewport() {
    if (!widget.scrollController.hasClients) return;
    final tagMap = widget.scrollController.tagMap;
    if (tagMap.isEmpty) {
      if (_visiblePostNumbersNotifier.value.isNotEmpty) {
        _visiblePostNumbersNotifier.value = const <int>{};
      }
      _lastVisiblePostNumbers = const <int>{};
      return;
    }

    final position = widget.scrollController.position;
    final viewportHeight = position.viewportDimension;
    final topBoundary =
        widget.topBoundaryHeight + MediaQuery.of(context).padding.top;
    final eyeline = topBoundary;
    final visiblePostNumbers = <int>{};
    int? eyelinePostNumber;
    int? closestPostNumber;
    double closestDistance = double.infinity;
    final staleTagKeys = <int>[];

    for (final entry in tagMap.entries) {
      final postNumber = _scrollIndexRegistry.postNumberFor(entry.key);
      if (postNumber == null) {
        staleTagKeys.add(entry.key);
        continue;
      }

      final ctx = entry.value.context;
      if (!ctx.mounted) {
        staleTagKeys.add(entry.key);
        continue;
      }
      final RenderBox? renderBox;
      try {
        renderBox = ctx.findRenderObject() as RenderBox?;
      } catch (_) {
        staleTagKeys.add(entry.key);
        continue;
      }
      if (renderBox == null || !renderBox.hasSize || !renderBox.attached) {
        staleTagKeys.add(entry.key);
        continue;
      }

      final topY = renderBox.localToGlobal(Offset.zero).dy;
      final bottomY = topY + renderBox.size.height;

      if (topY < viewportHeight && bottomY > topBoundary) {
        visiblePostNumbers.add(postNumber);
      }

      if (topY <= eyeline && bottomY > eyeline) {
        eyelinePostNumber = postNumber;
      }

      final distance = topY > eyeline
          ? topY - eyeline
          : (bottomY < eyeline ? eyeline - bottomY : 0.0);
      if (distance < closestDistance) {
        closestDistance = distance;
        closestPostNumber = postNumber;
      }
    }

    if (staleTagKeys.isNotEmpty) {
      for (final key in staleTagKeys) {
        tagMap.remove(key);
      }
    }

    if (!setEquals(_visiblePostNumbersNotifier.value, visiblePostNumbers)) {
      _visiblePostNumbersNotifier.value = visiblePostNumbers.isEmpty
          ? const <int>{}
          : Set<int>.unmodifiable(visiblePostNumbers);
    }

    if (!setEquals(_lastVisiblePostNumbers, visiblePostNumbers)) {
      _lastVisiblePostNumbers = visiblePostNumbers.isEmpty
          ? const <int>{}
          : Set<int>.unmodifiable(visiblePostNumbers);
      if (visiblePostNumbers.isNotEmpty) {
        widget.onVisiblePostsChanged?.call(visiblePostNumbers);
      }
    }

    final currentPostNumber = eyelinePostNumber ?? closestPostNumber;
    if (currentPostNumber != null &&
        currentPostNumber != _lastReportedPostNumber) {
      _lastReportedPostNumber = currentPostNumber;
      widget.onFirstVisiblePostChanged?.call(currentPostNumber);
    }
  }

  /// 根据设备类型计算最大嵌套深度
  int _getMaxDepth(BuildContext context) {
    return switch (Responsive.getDeviceType(context)) {
      DeviceType.mobile => 5,
      DeviceType.tablet => 7,
      DeviceType.desktop => 10,
    };
  }

  int get _maxNestedRepliesCacheEntries => Responsive.isMobile(context)
      ? _maxNestedRepliesCacheEntriesMobile
      : _maxNestedRepliesCacheEntriesDesktop;

  Duration get _visiblePostUpdateDelay => Responsive.isMobile(context)
      ? _visiblePostUpdateDelayMobile
      : _visiblePostUpdateDelayDesktop;

  Duration get _autoChildLoadResumeDelay => Responsive.isMobile(context)
      ? _autoChildLoadResumeDelayMobile
      : _autoChildLoadResumeDelayDesktop;

  void _setAutoLoadChildrenPaused(bool paused) {
    _autoChildLoadResumeTimer?.cancel();
    if (_autoLoadChildrenPausedNotifier.value == paused) return;
    _autoLoadChildrenPausedNotifier.value = paused;
  }

  void _resumeAutoLoadChildren() {
    _autoChildLoadResumeTimer?.cancel();
    _autoChildLoadResumeTimer = Timer(_autoChildLoadResumeDelay, () {
      if (!mounted || !_autoLoadChildrenPausedNotifier.value) return;
      _autoLoadChildrenPausedNotifier.value = false;
    });
  }

  void _rememberRepliesState(int postNumber, NestedRepliesState state) {
    _repliesStateByPostNumber.remove(postNumber);
    _repliesStateByPostNumber[postNumber] = state;
    while (_repliesStateByPostNumber.length > _maxNestedRepliesCacheEntries) {
      _repliesStateByPostNumber.remove(_repliesStateByPostNumber.keys.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    _scrollIndexRegistry.reset();
    final maxDepth = _getMaxDepth(context);

    final ns = widget.nestedState;
    final p = widget.params;
    final opPost =
        ns.opPost != null &&
            !BlockedUserFilter.isBlockedUsername(
              ns.opPost!.username,
              widget.blockedUsernames,
            )
        ? ns.opPost
        : null;
    final roots = BlockedUserFilter.visibleNestedNodes(
      ns.roots,
      widget.blockedUsernames,
    );

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final result = widget.onScrollNotification(notification);
        if (notification is ScrollStartNotification ||
            notification is ScrollUpdateNotification) {
          _setAutoLoadChildrenPaused(true);
        }
        if (notification is ScrollEndNotification) {
          _resumeAutoLoadChildren();
          _scheduleVisiblePostsUpdate(immediate: true);
        }
        return result;
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            widget.onPointerScroll?.call(event.scrollDelta.dy);
          }
        },
        child: CustomScrollView(
          controller: widget.scrollController,
          cacheExtent: Responsive.isMobile(context) ? 160.0 : 500.0,
          slivers: [
            if (widget.topContentInset > 0)
              SliverToBoxAdapter(
                child: SizedBox(height: widget.topContentInset),
              ),
            SliverToBoxAdapter(
              child: SelectionContainer.disabled(
                child: TopicDetailHeader(
                  detail: widget.detail,
                  headerKey: widget.headerKey,
                  onVoteChanged: widget.onVoteChanged,
                  onNotificationLevelChanged: widget.onNotificationLevelChanged,
                  onJumpToPost: widget.onJumpToPost,
                  onContinueAiSummary: widget.onContinueAiSummary,
                ),
              ),
            ),

            if (opPost != null)
              SliverToBoxAdapter(
                child: AutoScrollTag(
                  key: const ValueKey('nested-post-1-op'),
                  controller: widget.scrollController,
                  index: _nextIndexForPost(opPost.postNumber),
                  child: PostItem(
                    post: opPost,
                    topicId: widget.topicId,
                    isTopicOwner: true,
                    topicHasAcceptedAnswer: widget.detail.hasAcceptedAnswer,
                    acceptedAnswers: widget.detail.acceptedAnswers,
                    relatedTopics: widget.detail.relatedTopics,
                    searchHighlightQuery: widget.searchHighlightQuery,
                    onReply: widget.isLoggedIn
                        ? () => widget.onReply(null)
                        : null,
                    onReplyWithInitialContent:
                        widget.isLoggedIn &&
                            widget.onReplyWithInitialContent != null
                        ? (initialContent) => widget.onReplyWithInitialContent!(
                            null,
                            initialContent,
                          )
                        : null,
                    onEdit: widget.isLoggedIn && opPost.canEdit
                        ? () => widget.onEdit(opPost)
                        : null,
                    onRefreshPost: widget.onRefreshPost,
                    onJumpToPost: widget.onJumpToPost,
                    onSolutionChanged: widget.onSolutionChanged,
                    hideRepliesButton: true,
                    sharedIssueVisible: widget.detail.sharedIssueVisible,
                    canCreateSharedIssue: widget.detail.canCreateSharedIssue,
                    sharedIssueCount: widget.detail.sharedIssueCount,
                    userCreatedSharedIssue:
                        widget.detail.userCreatedSharedIssue,
                    onSharedIssueChanged: widget.onSharedIssueChanged,
                    useUsernameAsPrimaryLabel: true,
                  ),
                ),
              ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    _SortChip(
                      label: context.l10n.nested_sortTop,
                      value: 'top',
                      current: ns.sort,
                      enabled: !ns.isRefreshingSort,
                      onTap: () => ref
                          .read(nestedTopicProvider(p).notifier)
                          .changeSort('top'),
                    ),
                    const SizedBox(width: 6),
                    _SortChip(
                      label: context.l10n.nested_sortNew,
                      value: 'new',
                      current: ns.sort,
                      enabled: !ns.isRefreshingSort,
                      onTap: () => ref
                          .read(nestedTopicProvider(p).notifier)
                          .changeSort('new'),
                    ),
                    const SizedBox(width: 6),
                    _SortChip(
                      label: context.l10n.nested_sortOld,
                      value: 'old',
                      current: ns.sort,
                      enabled: !ns.isRefreshingSort,
                      onTap: () => ref
                          .read(nestedTopicProvider(p).notifier)
                          .changeSort('old'),
                    ),
                  ],
                ),
              ),
            ),

            if (ns.isRefreshingSort)
              const SliverToBoxAdapter(child: TopicLinearLoadingIndicator()),

            if (ns.newRootPostIds.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: FilledButton.tonalIcon(
                    onPressed: () => ref
                        .read(nestedTopicProvider(p).notifier)
                        .loadNewRoots(),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    label: Text(
                      context.l10n.nested_newReplies(ns.newRootPostIds.length),
                    ),
                  ),
                ),
              ),

            SliverList.builder(
              itemCount:
                  roots.length + (ns.hasMoreRoots || ns.isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= roots.length) {
                  return _buildLoadMore(context);
                }
                return NestedPostCard(
                  key: ValueKey('nested-root-${roots[index].post.id}'),
                  node: roots[index],
                  topicId: widget.topicId,
                  detail: widget.detail,
                  params: p,
                  depth: 0,
                  maxDepth: maxDepth,
                  isLastChild: index == roots.length - 1,
                  isLoggedIn: widget.isLoggedIn,
                  blockedUsernames: widget.blockedUsernames,
                  onReply: widget.onReply,
                  onReplyWithInitialContent: widget.onReplyWithInitialContent,
                  onEdit: widget.onEdit,
                  onRefreshPost: widget.onRefreshPost,
                  onJumpToPost: widget.onJumpToPost,
                  onSolutionChanged: widget.onSolutionChanged,
                  expansionState: _expansionState,
                  repliesStateByPostNumber: _repliesStateByPostNumber,
                  onRepliesStateChanged: (postNumber, state) {
                    _rememberRepliesState(postNumber, state);
                    _scheduleVisiblePostsUpdateAfterLayout();
                  },
                  autoLoadChildrenPausedListenable:
                      _autoLoadChildrenPausedNotifier,
                  autoWorkVisiblePostNumbersListenable:
                      _visiblePostNumbersNotifier,
                  searchHighlightQuery: widget.searchHighlightQuery,
                  buildScrollTag: (postNumber, child) => AutoScrollTag(
                    key: ValueKey('nested-post-$postNumber'),
                    controller: widget.scrollController,
                    index: _nextIndexForPost(postNumber),
                    child: child,
                  ),
                );
              },
            ),

            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.of(context).padding.bottom + 100,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadMore(BuildContext context) {
    final ns = widget.nestedState;
    final p = widget.params;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ns.isLoadingMore
          ? const TopicLinearLoadingIndicator(
              padding: EdgeInsets.symmetric(horizontal: 0),
            )
          : Center(
              child: TextButton(
                onPressed: () =>
                    ref.read(nestedTopicProvider(p).notifier).loadMoreRoots(),
                child: Text(context.l10n.nested_loadMore),
              ),
            ),
    );
  }
}

/// 排序 Chip
class _SortChip extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final bool enabled;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.value,
    required this.current,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = value == current;
    return GestureDetector(
      onTap: !enabled || isActive ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: !enabled
                ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55)
                : isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
