import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import '../../../l10n/s.dart';
import '../../../models/nested_topic.dart';
import '../../../models/topic.dart';
import '../../../providers/nested_topic_provider.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/nested/nested_post_card.dart';
import '../../../widgets/post/post_item/post_item.dart';
import 'topic_detail_header.dart';

/// 嵌套视图帖子列表 — 在现有 TopicDetailPage 内替换平铺帖子流
class NestedPostList extends ConsumerStatefulWidget {
  final NestedTopicState nestedState;
  final NestedTopicParams params;
  final TopicDetail detail;
  final int topicId;
  final AutoScrollController scrollController;
  final GlobalKey headerKey;
  final bool isLoggedIn;
  final void Function(Post? replyToPost) onReply;
  final void Function(Post post) onEdit;
  final void Function(int postId) onRefreshPost;
  final void Function(int postNumber) onJumpToPost;
  final void Function(int, bool) onVoteChanged;
  final void Function(TopicNotificationLevel)? onNotificationLevelChanged;
  final void Function(int postId, bool accepted)? onSolutionChanged;
  final bool Function(ScrollNotification) onScrollNotification;
  final ValueChanged<double>? onPointerScroll;
  final void Function(Map<int, int>)? onPostNumberScrollIndexMappingChanged;
  final void Function(TopicSummary summary)? onContinueAiSummary;

  /// 可见帖子上报（走 ScreenTrack 上报链路）
  final void Function(Set<int> visiblePostNumbers)? onVisiblePostsChanged;

  const NestedPostList({
    super.key,
    required this.nestedState,
    required this.params,
    required this.detail,
    required this.topicId,
    required this.scrollController,
    required this.headerKey,
    required this.isLoggedIn,
    required this.onReply,
    required this.onEdit,
    required this.onRefreshPost,
    required this.onJumpToPost,
    required this.onVoteChanged,
    this.onNotificationLevelChanged,
    this.onSolutionChanged,
    required this.onScrollNotification,
    this.onPointerScroll,
    this.onPostNumberScrollIndexMappingChanged,
    this.onContinueAiSummary,
    this.onVisiblePostsChanged,
  });

  @override
  ConsumerState<NestedPostList> createState() => _NestedPostListState();
}

class _NestedPostListState extends ConsumerState<NestedPostList> {
  final Map<int, bool> _expansionState = {};
  final Map<int, int> _postNumberToScrollIndex = {};
  bool _hasReachedLoadMoreRegion = false;
  double? _lastScrollPixels;
  int _nextScrollIndex = 0;

  /// 当前正在渲染的根帖子号集合（SliverList.builder 渲染时收集）
  final Set<int> _builtPostNumbers = {};

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    // 上报当前可见帖子
    if (_builtPostNumbers.isNotEmpty) {
      widget.onVisiblePostsChanged?.call(Set.from(_builtPostNumbers));
    }

    if (!widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    final previousPixels = _lastScrollPixels;
    final scrollingTowardBottom =
        previousPixels != null && position.pixels > previousPixels + 4;
    _lastScrollPixels = position.pixels;

    final ns = widget.nestedState;
    if (!ns.hasMoreRoots || ns.isLoadingMore) {
      _hasReachedLoadMoreRegion = false;
      return;
    }

    final nearLoadMore = position.pixels >= position.maxScrollExtent - 360;
    if (!nearLoadMore) {
      _hasReachedLoadMoreRegion = false;
      return;
    }

    if (!_hasReachedLoadMoreRegion) {
      _hasReachedLoadMoreRegion = true;
      return;
    }

    if (scrollingTowardBottom) {
      _hasReachedLoadMoreRegion = false;
      ref.read(nestedTopicProvider(widget.params).notifier).loadMoreRoots();
    }
  }

  int _nextIndexForPost(int postNumber) {
    final index = _nextScrollIndex++;
    _postNumberToScrollIndex[postNumber] = index;
    widget.onPostNumberScrollIndexMappingChanged?.call(
      Map<int, int>.from(_postNumberToScrollIndex),
    );
    return index;
  }

  /// 递归收集节点及其展开子节点中的所有 postNumber
  void _collectVisiblePostNumbers(NestedNode node) {
    _builtPostNumbers.add(node.post.postNumber);
    final expanded =
        _expansionState[node.post.postNumber] ?? node.children.isNotEmpty;
    if (expanded) {
      for (final child in node.children) {
        _collectVisiblePostNumbers(child);
      }
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

  @override
  Widget build(BuildContext context) {
    _builtPostNumbers.clear();
    _postNumberToScrollIndex.clear();
    _nextScrollIndex = 0;
    final maxDepth = _getMaxDepth(context);

    // OP 也算可见
    final ns = widget.nestedState;
    if (ns.opPost != null) _builtPostNumbers.add(ns.opPost!.postNumber);
    final p = widget.params;

    return NotificationListener<ScrollNotification>(
      onNotification: widget.onScrollNotification,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            widget.onPointerScroll?.call(event.scrollDelta.dy);
          }
        },
        child: CustomScrollView(
          controller: widget.scrollController,
          slivers: [
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

            if (ns.opPost != null)
              SliverToBoxAdapter(
                child: AutoScrollTag(
                  key: const ValueKey('nested-post-1-op'),
                  controller: widget.scrollController,
                  index: _nextIndexForPost(ns.opPost!.postNumber),
                  child: PostItem(
                    post: ns.opPost!,
                    topicId: widget.topicId,
                    isTopicOwner: true,
                    topicHasAcceptedAnswer: widget.detail.hasAcceptedAnswer,
                    acceptedAnswerPostNumber:
                        widget.detail.acceptedAnswerPostNumber,
                    onReply: widget.isLoggedIn
                        ? () => widget.onReply(null)
                        : null,
                    onEdit: widget.isLoggedIn && ns.opPost!.canEdit
                        ? () => widget.onEdit(ns.opPost!)
                        : null,
                    onRefreshPost: widget.onRefreshPost,
                    onJumpToPost: widget.onJumpToPost,
                    onSolutionChanged: widget.onSolutionChanged,
                    hideRepliesButton: true,
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
                      onTap: () => ref
                          .read(nestedTopicProvider(p).notifier)
                          .changeSort('top'),
                    ),
                    const SizedBox(width: 6),
                    _SortChip(
                      label: context.l10n.nested_sortNew,
                      value: 'new',
                      current: ns.sort,
                      onTap: () => ref
                          .read(nestedTopicProvider(p).notifier)
                          .changeSort('new'),
                    ),
                    const SizedBox(width: 6),
                    _SortChip(
                      label: context.l10n.nested_sortOld,
                      value: 'old',
                      current: ns.sort,
                      onTap: () => ref
                          .read(nestedTopicProvider(p).notifier)
                          .changeSort('old'),
                    ),
                  ],
                ),
              ),
            ),

            SliverList.builder(
              itemCount:
                  ns.roots.length +
                  (ns.hasMoreRoots || ns.isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= ns.roots.length) {
                  return _buildLoadMore(context);
                }
                // 收集可见帖子号（含子节点）
                _collectVisiblePostNumbers(ns.roots[index]);
                return NestedPostCard(
                  node: ns.roots[index],
                  topicId: widget.topicId,
                  detail: widget.detail,
                  params: p,
                  depth: 0,
                  maxDepth: maxDepth,
                  isLastChild: index == ns.roots.length - 1,
                  isLoggedIn: widget.isLoggedIn,
                  onReply: widget.onReply,
                  onEdit: widget.onEdit,
                  onRefreshPost: widget.onRefreshPost,
                  onJumpToPost: widget.onJumpToPost,
                  onSolutionChanged: widget.onSolutionChanged,
                  expansionState: _expansionState,
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
          ? const Center(child: CircularProgressIndicator())
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
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.value,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = value == current;
    return GestureDetector(
      onTap: isActive ? null : onTap,
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
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
