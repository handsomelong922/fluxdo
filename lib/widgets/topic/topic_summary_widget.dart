import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../models/topic.dart';
import '../../pages/topic_detail_page/topic_detail_page.dart';
import '../../services/topic_ai/topic_ai_context_service.dart';
import '../../services/topic_ai/topic_ai_summary_service.dart';
import '../common/relative_time_text.dart';
import '../markdown_editor/markdown_renderer.dart';

/// 话题 AI 摘要组件
class TopicSummaryWidget extends ConsumerStatefulWidget {
  final int topicId;
  final TopicDetail topicDetail;

  /// 跳转到当前话题的指定帖子
  final void Function(int postNumber)? onJumpToPost;

  const TopicSummaryWidget({
    super.key,
    required this.topicId,
    required this.topicDetail,
    this.onJumpToPost,
  });

  @override
  ConsumerState<TopicSummaryWidget> createState() => _TopicSummaryWidgetState();
}

class _TopicSummaryWidgetState extends ConsumerState<TopicSummaryWidget> {
  AsyncValue<TopicSummary?> _summaryAsync = const AsyncValue.loading();
  List<TopicAiContextPost> _cachedPosts = const [];

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  @override
  void didUpdateWidget(covariant TopicSummaryWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.topicId != widget.topicId) {
      _cachedPosts = const [];
      _loadSummary();
    }
  }

  Future<void> _loadSummary() async {
    setState(() {
      _summaryAsync = const AsyncValue.loading();
    });

    try {
      final posts = await ref
          .read(topicAiContextServiceProvider)
          .loadContextPosts(
            topicId: widget.topicId,
            detail: widget.topicDetail,
            scope: ContextScope.all,
            fetchPosts: ref.read(topicAiPostsFetcherProvider),
            cachedPosts: _cachedPosts,
          );
      final summary = await ref
          .read(topicAiSummaryServiceProvider)
          .generateSummary(
            topicId: widget.topicId,
            detail: widget.topicDetail,
            cachedPosts: posts,
          );
      if (!mounted) return;
      setState(() {
        _cachedPosts = posts;
        _summaryAsync = AsyncValue.data(summary);
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _summaryAsync = AsyncValue.error(error, stackTrace);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            alignment: Alignment.topCenter,
            children: <Widget>[
              ...previousChildren,
              currentChild ?? const SizedBox.shrink(),
            ],
          );
        },
        child: _summaryAsync.when(
          loading: () => KeyedSubtree(
            key: const ValueKey('loading'),
            child: _buildLoadingState(theme),
          ),
          error: (error, stack) => KeyedSubtree(
            key: const ValueKey('error'),
            child: _buildErrorState(theme),
          ),
          data: (summary) {
            if (summary == null) {
              return KeyedSubtree(
                key: const ValueKey('empty'),
                child: _buildEmptyState(theme),
              );
            }
            return KeyedSubtree(
              key: const ValueKey('data'),
              child: _buildSummaryContent(context, theme, summary),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoadingState(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            S.current.topic_generatingSummary,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              S.current.topic_summaryLoadFailed,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          TextButton(
            onPressed: _loadSummary,
            child: Text(S.current.common_retry),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Text(
            S.current.topic_noSummary,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryContent(
    BuildContext context,
    ThemeData theme,
    TopicSummary summary,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                S.current.topic_aiSummary,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          MarkdownBody(
            data: summary.summarizedText,
            onInternalLinkTap: (linkTopicId, topicSlug, postNumber) {
              if (linkTopicId == widget.topicId &&
                  postNumber != null &&
                  widget.onJumpToPost != null) {
                widget.onJumpToPost!(postNumber);
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TopicDetailPage(
                      topicId: linkTopicId,
                      initialTitle: topicSlug,
                      scrollToPostNumber: postNumber,
                    ),
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (summary.updatedAt != null)
                RelativeTimeText(
                  dateTime: summary.updatedAt!,
                  displayStyle: TimeDisplayStyle.prefixed,
                  prefix: S.current.topic_updatedAt,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const Spacer(),
              if (summary.canRegenerate)
                TextButton.icon(
                  onPressed: _loadSummary,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(S.current.common_refresh),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 可折叠的话题摘要组件（懒加载：点击时才请求）
class CollapsibleTopicSummary extends ConsumerStatefulWidget {
  final int topicId;
  final TopicDetail? topicDetail;
  final Widget? headerExtra;
  final bool initiallyExpanded;

  /// 跳转到当前话题的指定帖子
  final void Function(int postNumber)? onJumpToPost;

  const CollapsibleTopicSummary({
    super.key,
    required this.topicId,
    this.topicDetail,
    this.headerExtra,
    this.initiallyExpanded = false,
    this.onJumpToPost,
  });

  @override
  ConsumerState<CollapsibleTopicSummary> createState() =>
      _CollapsibleTopicSummaryState();
}

class _CollapsibleTopicSummaryState
    extends ConsumerState<CollapsibleTopicSummary>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  bool _hasRequested = false;
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _isExpanded = widget.initiallyExpanded;
    _hasRequested = widget.initiallyExpanded;
    if (_isExpanded) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant CollapsibleTopicSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isExpanded &&
        widget.initiallyExpanded &&
        !oldWidget.initiallyExpanded) {
      _isExpanded = true;
      _hasRequested = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              onTap: _toggleExpand,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _hasRequested
                          ? S.current.topic_aiSummary
                          : S.current.topic_generateAiSummary,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.expand_more,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.headerExtra != null) ...[
              const SizedBox(width: 12),
              widget.headerExtra!,
            ],
          ],
        ),
        SizeTransition(
          sizeFactor: _animation,
          axisAlignment: -1.0,
          child: _hasRequested && widget.topicDetail != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TopicSummaryWidget(
                    topicId: widget.topicId,
                    topicDetail: widget.topicDetail!,
                    onJumpToPost: widget.onJumpToPost,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
        if (!_hasRequested) {
          _hasRequested = true;
        }
      } else {
        _controller.reverse();
      }
    });
  }
}
