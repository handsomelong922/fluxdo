import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../../l10n/s.dart';
import '../../../../../constants.dart';
import '../../../../../models/topic.dart';
import '../../../../../modules/ldc_reward/ldc_reward.dart';
import '../../../../../providers/discourse_providers.dart';
import '../../../../../providers/preferences_provider.dart';
import 'package:dio/dio.dart';
import '../../../../../services/app_error_handler.dart';
import '../../../../../services/discourse/discourse_service.dart';
import '../../../../../services/network/exceptions/api_exception.dart';
import '../../../../../services/toast_service.dart';
import '../../../post_links.dart';
import '../post_action_bar.dart';
import '../../../../bookmark/bookmark_edit_sheet.dart';
import '../../../../post/post_boost/boost_list.dart';
import '../../../../post/post_boost/boost_input.dart';
import '../../../../post/reply_auto_expand_policy.dart';
import '../post_flag_sheet.dart';
import '../post_reaction_picker.dart';
import '../post_reaction_users_sheet.dart';
import '../post_replies_list.dart';
import '../post_solution_banner.dart';
import '../../../../post/post_replies_sheet.dart';
import '../../../../../utils/dialog_utils.dart';

part 'actions/bookmark_actions.dart';
part 'actions/manage_actions.dart';
part 'actions/menu_actions.dart';
part 'actions/reaction_actions.dart';
part 'actions/reply_actions.dart';

class InlineRepliesState {
  const InlineRepliesState({required this.replies, required this.showReplies});

  final List<Post> replies;
  final bool showReplies;
}

class PostFooterSection extends ConsumerStatefulWidget {
  final Post post;
  final int topicId;
  final bool topicHasAcceptedAnswer;
  final List<AcceptedAnswer> acceptedAnswers;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onReply;
  final void Function(String initialContent)? onReplyWithInitialContent;
  final VoidCallback? onEdit;
  final VoidCallback? onShareAsImage;
  final void Function(int postId)? onRefreshPost;
  final void Function(int postNumber)? onJumpToPost;
  final void Function(int postId, bool accepted)? onSolutionChanged;
  final ValueChanged<bool>? onAcceptedAnswerChanged;
  final bool useReplyDialog;

  /// 隐藏回复列表按钮（弹框内使用时不需要展示）
  final bool hideRepliesButton;

  /// 查看帖子详情回调（菜单中的"查看帖子详情"或"跳转"）
  final VoidCallback? onShowPostDetail;

  /// 自定义帖子详情菜单项文本（默认"帖子详情"，弹框中可用"跳转"）
  final String? postDetailLabel;

  /// Boost 更新回调
  final void Function(Post updatedPost)? onBoostUpdated;

  /// 高亮指定用户的 boost（从 boost 通知跳转时使用）
  final String? highlightBoostUsername;

  /// 内联回复展开状态缓存（由虚拟列表的父级持有，避免滚动回收后抖动）。
  final InlineRepliesState? inlineRepliesState;
  final ValueChanged<InlineRepliesState>? onInlineRepliesStateChanged;
  final bool sharedIssueVisible;
  final bool canCreateSharedIssue;
  final int sharedIssueCount;
  final bool userCreatedSharedIssue;
  final void Function(int count, bool userCreated)? onSharedIssueChanged;

  const PostFooterSection({
    super.key,
    required this.post,
    required this.topicId,
    required this.topicHasAcceptedAnswer,
    this.acceptedAnswers = const [],
    required this.padding,
    required this.onReply,
    this.onReplyWithInitialContent,
    required this.onEdit,
    required this.onShareAsImage,
    required this.onRefreshPost,
    required this.onJumpToPost,
    required this.onSolutionChanged,
    this.onAcceptedAnswerChanged,
    this.useReplyDialog = false,
    this.hideRepliesButton = false,
    this.onShowPostDetail,
    this.postDetailLabel,
    this.onBoostUpdated,
    this.highlightBoostUsername,
    this.inlineRepliesState,
    this.onInlineRepliesStateChanged,
    this.sharedIssueVisible = false,
    this.canCreateSharedIssue = false,
    this.sharedIssueCount = 0,
    this.userCreatedSharedIssue = false,
    this.onSharedIssueChanged,
  });

  @override
  ConsumerState<PostFooterSection> createState() => _PostFooterSectionState();
}

class _PostFooterSectionState extends ConsumerState<PostFooterSection> {
  final DiscourseService _service = DiscourseService();
  final GlobalKey _likeButtonKey = GlobalKey();
  bool _isLiking = false;
  bool _isBookmarked = false;
  int? _bookmarkId;
  String? _bookmarkName;
  DateTime? _bookmarkReminderAt;
  bool _isBookmarking = false;
  late List<PostReaction> _reactions;
  PostReaction? _currentUserReaction;
  late List<Boost> _boosts;
  late bool _canBoost;
  final List<Post> _replies = [];
  final ValueNotifier<bool> _isLoadingRepliesNotifier = ValueNotifier<bool>(
    false,
  );
  late final ValueNotifier<bool> _showRepliesNotifier;
  bool _isAcceptedAnswer = false;
  bool _isTogglingAnswer = false;
  bool _isDeleting = false;
  bool _autoReplyLoadScheduled = false;

  bool get _canLoadMoreReplies => _replies.length < widget.post.replyCount;
  bool get _shouldAutoExpandReplies =>
      !widget.hideRepliesButton &&
      !widget.useReplyDialog &&
      shouldAutoExpandReplyCount(widget.post.replyCount);
  InlineRepliesState? get _restorableInlineRepliesState =>
      widget.useReplyDialog ? null : widget.inlineRepliesState;

  @override
  void initState() {
    super.initState();
    final inlineState = _restorableInlineRepliesState;
    _replies.addAll(inlineState?.replies ?? const []);
    _showRepliesNotifier = ValueNotifier<bool>(
      inlineState?.showReplies ?? _shouldAutoExpandReplies,
    )..addListener(_emitInlineRepliesState);
    _syncState();
    _scheduleAutoLoadReplies();
  }

  @override
  void didUpdateWidget(PostFooterSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post != widget.post) {
      if (oldWidget.post.id != widget.post.id) {
        final inlineState = _restorableInlineRepliesState;
        _replies.clear();
        _replies.addAll(inlineState?.replies ?? const []);
        _showRepliesNotifier.value =
            inlineState?.showReplies ?? _shouldAutoExpandReplies;
        _autoReplyLoadScheduled = false;
      }
      _syncState();
      _syncReplyExpansionState();
    } else if (oldWidget.useReplyDialog != widget.useReplyDialog) {
      _showRepliesNotifier.value =
          _restorableInlineRepliesState?.showReplies ??
          _shouldAutoExpandReplies;
      _syncReplyExpansionState();
    }
  }

  @override
  void dispose() {
    _isLoadingRepliesNotifier.dispose();
    _showRepliesNotifier.removeListener(_emitInlineRepliesState);
    _showRepliesNotifier.dispose();
    super.dispose();
  }

  void _syncState() {
    _reactions = List.from(widget.post.reactions ?? []);
    _currentUserReaction = widget.post.currentUserReaction;
    _isBookmarked = widget.post.bookmarked;
    _bookmarkId = widget.post.bookmarkId;
    _bookmarkName = widget.post.bookmarkName;
    _bookmarkReminderAt = widget.post.bookmarkReminderAt;
    _isAcceptedAnswer = widget.post.acceptedAnswer;
    _boosts = _dedupeBoostsById(widget.post.boosts ?? const []);
    _canBoost = widget.post.canBoost;
  }

  void _syncReplyExpansionState() {
    final hasCachedState = _restorableInlineRepliesState != null;
    if (!hasCachedState &&
        _shouldAutoExpandReplies &&
        !_showRepliesNotifier.value) {
      _showRepliesNotifier.value = true;
      _emitInlineRepliesState();
    }
    _scheduleAutoLoadReplies();
  }

  void _emitInlineRepliesState() {
    widget.onInlineRepliesStateChanged?.call(
      InlineRepliesState(
        replies: List<Post>.unmodifiable(_replies),
        showReplies: _showRepliesNotifier.value,
      ),
    );
  }

  void _scheduleAutoLoadReplies() {
    if (!_shouldAutoExpandReplies ||
        _replies.isNotEmpty ||
        _isLoadingRepliesNotifier.value ||
        _autoReplyLoadScheduled) {
      return;
    }

    _autoReplyLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoReplyLoadScheduled = false;
      if (!mounted ||
          !_shouldAutoExpandReplies ||
          _replies.isNotEmpty ||
          _isLoadingRepliesNotifier.value) {
        return;
      }
      _showRepliesNotifier.value = true;
      _emitInlineRepliesState();
      _loadReplies();
    });
  }

  Future<void> _handleBoostCreated(Boost boost) async {
    if (!mounted) return;
    setState(() {
      _boosts = _dedupeBoostsById([..._boosts, boost]);
      _canBoost = false;
    });
    widget.onBoostUpdated?.call(
      widget.post.copyWith(boosts: List.from(_boosts), canBoost: _canBoost),
    );
  }

  void _handleBoostDeleted(Boost boost) {
    if (!mounted) return;
    setState(() {
      _boosts.removeWhere((b) => b.id == boost.id);
      final currentUser = ref.read(currentUserProvider).value;
      if (currentUser != null && boost.user.username == currentUser.username) {
        _canBoost = true;
      }
    });
    widget.onBoostUpdated?.call(
      widget.post.copyWith(boosts: List.from(_boosts), canBoost: _canBoost),
    );
  }

  List<Boost> _dedupeBoostsById(List<Boost> boosts) {
    final byId = <int, Boost>{};
    for (final boost in boosts) {
      byId[boost.id] = boost;
    }
    return byId.values.toList(growable: false);
  }

  Future<void> _deleteBoost(Boost boost) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(S.current.boost_deleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.current.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              S.current.common_delete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _service.deleteBoost(boost.id);
      if (!mounted) return;
      _handleBoostDeleted(boost);
      ToastService.showSuccess(S.current.boost_deleted);
    } catch (_) {
      if (!mounted) return;
      ToastService.showError(S.current.boost_deleteFailed);
    }
  }

  void _showBoostActions(Boost boost) {
    final currentUser = ref.read(currentUserProvider).value;
    final isOwn =
        currentUser != null && boost.user.username == currentUser.username;

    if (!isOwn && !boost.canDelete) return;

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(S.current.common_delete),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteBoost(boost);
                },
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: Text(S.current.common_cancel),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openBoostInput() async {
    final result = await showBoostInputSheet(context);
    if (result == null || !mounted) return;

    final raw = result.raw;
    if (raw.isEmpty) return;

    if (result is BoostInputReplyResult) {
      if (widget.onReplyWithInitialContent != null) {
        widget.onReplyWithInitialContent!('$raw\n\n');
      } else if (widget.onReply != null) {
        ToastService.showInfo(S.current.boost_tooLong(16));
        widget.onReply!();
      }
      return;
    }

    await _createBoost(raw);
  }

  Future<void> _createBoost(String raw) async {
    try {
      final boost = await _service.createBoost(widget.post.id, raw);
      if (!mounted) return;
      _handleBoostCreated(boost);
      ToastService.showSuccess(S.current.boost_created);
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(S.current.boost_failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = ref.read(currentUserProvider).value;
    final isOwnPost =
        currentUser != null && currentUser.username == widget.post.username;
    final isGuest = currentUser == null;

    // 预热打赏凭证，避免首次打开更多菜单时因 AsyncLoading 导致打赏选项不显示
    ref.watch(ldcRewardCredentialsProvider);

    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PostLinks(
            linkCounts: widget.post.linkCounts,
            defaultExpanded: ref.watch(preferencesProvider).expandRelatedLinks,
          ),
          if (widget.post.postNumber == 1 &&
              widget.topicHasAcceptedAnswer &&
              widget.acceptedAnswers.isNotEmpty)
            PostSolutionBanner(
              acceptedAnswers: widget.acceptedAnswers,
              onJumpToPost: widget.onJumpToPost,
            ),
          if (widget.post.postNumber == 1 && widget.sharedIssueVisible)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _SharedIssueButton(
                topicId: widget.topicId,
                canCreateSharedIssue: widget.canCreateSharedIssue,
                count: widget.sharedIssueCount,
                userCreated: widget.userCreatedSharedIssue,
                onChanged: widget.onSharedIssueChanged,
              ),
            ),
          const SizedBox(height: 12),
          PostActionBar(
            post: widget.post,
            isGuest: isGuest,
            isOwnPost: isOwnPost,
            isLiking: _isLiking,
            reactions: _reactions,
            currentUserReaction: _currentUserReaction,
            likeButtonKey: _likeButtonKey,
            replies: _replies,
            isLoadingRepliesNotifier: _isLoadingRepliesNotifier,
            showRepliesNotifier: _showRepliesNotifier,
            hideRepliesButton: widget.hideRepliesButton,
            onToggleLike: _toggleLike,
            onShowReactionPicker: () => _showReactionPicker(context, theme),
            onShowReactionUsers: (reactionId) =>
                _showReactionUsers(context, reactionId: reactionId),
            onReply: widget.onReply,
            onShowMoreMenu: () => _showMoreMenu(context, theme),
            onToggleReplies: _toggleReplies,
            onAddBoost: _openBoostInput,
            canBoost: _canBoost,
            hasBoosts: _boosts.isNotEmpty,
          ),
          // Boost 气泡列表
          if (_boosts.isNotEmpty)
            BoostList(
              boosts: _boosts,
              canBoost: _canBoost,
              onAddBoost: _openBoostInput,
              onBoostTap: _showBoostActions,
              highlightUsername: widget.highlightBoostUsername,
            ),
          ValueListenableBuilder<bool>(
            valueListenable: _showRepliesNotifier,
            builder: (context, showReplies, _) {
              if (!showReplies) return const SizedBox.shrink();
              return PostRepliesList(
                replies: _replies,
                replyCount: widget.post.replyCount,
                canLoadMore: _canLoadMoreReplies,
                isLoadingRepliesNotifier: _isLoadingRepliesNotifier,
                showRepliesNotifier: _showRepliesNotifier,
                onLoadMore: _loadReplies,
                onJumpToPost: widget.onJumpToPost,
                contentFontScale: ref
                    .watch(preferencesProvider)
                    .contentFontScale,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SharedIssueButton extends ConsumerStatefulWidget {
  const _SharedIssueButton({
    required this.topicId,
    required this.canCreateSharedIssue,
    required this.count,
    required this.userCreated,
    this.onChanged,
  });

  final int topicId;
  final bool canCreateSharedIssue;
  final int count;
  final bool userCreated;
  final void Function(int count, bool userCreated)? onChanged;

  @override
  ConsumerState<_SharedIssueButton> createState() => _SharedIssueButtonState();
}

class _SharedIssueButtonState extends ConsumerState<_SharedIssueButton> {
  bool _isLoading = false;
  late int _count;
  late bool _userCreated;

  @override
  void initState() {
    super.initState();
    _count = widget.count;
    _userCreated = widget.userCreated;
  }

  @override
  void didUpdateWidget(covariant _SharedIssueButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count ||
        oldWidget.userCreated != widget.userCreated) {
      _count = widget.count;
      _userCreated = widget.userCreated;
    }
  }

  Future<void> _toggle() async {
    if (_isLoading) return;

    final user = ref.read(currentUserProvider).value;
    if (user == null) {
      ToastService.showInfo(S.current.vote_pleaseLogin);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await ref
          .read(discourseServiceProvider)
          .toggleSharedIssue(widget.topicId);
      if (!mounted) return;
      setState(() {
        _count = response.count;
        _userCreated = response.userCreatedSharedIssue;
        _isLoading = false;
      });
      widget.onChanged?.call(response.count, response.userCreatedSharedIssue);
      ToastService.showSuccess(
        response.userCreatedSharedIssue ? '已标记“俺也一样”' : '已取消“俺也一样”',
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (e.response?.statusCode == 429) {
        ToastService.showInfo('操作太频繁，请稍后再试');
      }
    } on RateLimitException {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ToastService.showInfo('操作太频繁，请稍后再试');
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = !widget.canCreateSharedIssue;
    final foreground = _userCreated
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.primary;
    final background = _userCreated
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHigh;

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled || _isLoading ? null : _toggle,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _userCreated
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isLoading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(foreground),
                  ),
                )
              else
                Icon(
                  _userCreated
                      ? Icons.front_hand_rounded
                      : Icons.front_hand_outlined,
                  size: 18,
                  color: foreground,
                ),
              const SizedBox(width: 6),
              Text(
                '俺也一样',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: _userCreated
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _userCreated
                        ? theme.colorScheme.onPrimary.withValues(alpha: 0.2)
                        : theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$_count',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: _userCreated
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return Opacity(
      opacity: disabled ? 0.7 : 1,
      child: Tooltip(
        message: disabled ? '作者不能对自己的主题标记“俺也一样”' : '俺也一样',
        child: button,
      ),
    );
  }
}
