import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/topic.dart';
import '../../../l10n/s.dart';
import '../../../providers/preferences_provider.dart';
import '../../../utils/code_selection_context.dart';
import '../../../utils/topic_link_navigation.dart';
import '../../content/discourse_html_content/chunked/chunked_html_content.dart';
import '../post_signature.dart';
import '../small_action_item.dart';
import 'quote_selection_helper.dart';
import 'widgets/post_footer_section/post_footer_section.dart';
import 'widgets/post_header_section.dart';
import 'widgets/post_notice_widget.dart';
import 'widgets/post_segment_frame.dart';
import 'widgets/accepted_solution_marker.dart';

class PostItem extends ConsumerStatefulWidget {
  final Post post;
  final int topicId;
  final VoidCallback? onReply;
  final void Function(String initialContent)? onReplyWithInitialContent;
  final VoidCallback? onLike;
  final VoidCallback? onEdit;
  final VoidCallback? onShareAsImage;
  final void Function(int postId)? onRefreshPost;
  final void Function(int postNumber)? onJumpToPost;
  final void Function(int postId, bool accepted)? onSolutionChanged;
  final bool highlight;
  final bool isTopicOwner;
  final bool topicHasAcceptedAnswer;
  final List<AcceptedAnswer> acceptedAnswers;
  final String? dateSeparatorLabel;
  final String? bottomDateSeparatorLabel;
  final void Function(String selectedText, Post post)? onQuoteSelection;
  final void Function(String quote, Post post)? onQuoteImage;
  final void Function(int postId)? onExpandHiddenPost;
  final bool useReplyDialog;
  final VoidCallback? onShowPostDetail;
  final bool hideRepliesButton;
  final String? highlightBoostUsername;
  final InlineRepliesState? inlineRepliesState;
  final ValueChanged<InlineRepliesState>? onInlineRepliesStateChanged;
  final String? searchHighlightQuery;

  const PostItem({
    super.key,
    required this.post,
    required this.topicId,
    this.onReply,
    this.onReplyWithInitialContent,
    this.onLike,
    this.onEdit,
    this.onShareAsImage,
    this.onRefreshPost,
    this.onJumpToPost,
    this.onSolutionChanged,
    this.highlight = false,
    this.highlightBoostUsername,
    this.isTopicOwner = false,
    this.topicHasAcceptedAnswer = false,
    this.acceptedAnswers = const [],
    this.dateSeparatorLabel,
    this.bottomDateSeparatorLabel,
    this.onQuoteSelection,
    this.onQuoteImage,
    this.onExpandHiddenPost,
    this.useReplyDialog = false,
    this.onShowPostDetail,
    this.hideRepliesButton = false,
    this.inlineRepliesState,
    this.onInlineRepliesStateChanged,
    this.searchHighlightQuery,
  });

  @override
  ConsumerState<PostItem> createState() => _PostItemState();
}

class _PostItemState extends ConsumerState<PostItem> {
  SelectedContent? _lastSelectedContent;
  CodeSelectionContext? _lastCodeSelectionContext;
  late bool _acceptedAnswer;

  @override
  void initState() {
    super.initState();
    _acceptedAnswer = _isAcceptedAnswer(widget);
  }

  @override
  void didUpdateWidget(PostItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post != widget.post ||
        oldWidget.acceptedAnswers != widget.acceptedAnswers) {
      _acceptedAnswer = _isAcceptedAnswer(widget);
    }
  }

  bool _isAcceptedAnswer(PostItem candidate) {
    return candidate.post.acceptedAnswer ||
        candidate.acceptedAnswers.any(
          (answer) => answer.postNumber == candidate.post.postNumber,
        );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final theme = Theme.of(context);

    if (post.postType == PostTypes.smallAction) {
      return SmallActionItem(post: post);
    }

    final isModeratorAction = post.postType == PostTypes.moderatorAction;
    return PostSegmentFrame(
      post: post,
      highlight: widget.highlight,
      constraints: const BoxConstraints(minHeight: 80),
      showTopDateSeparator: widget.dateSeparatorLabel != null,
      topDateSeparatorLabel: widget.dateSeparatorLabel,
      showBottomDateSeparator: widget.bottomDateSeparatorLabel != null,
      bottomDateSeparatorLabel: widget.bottomDateSeparatorLabel,
      showBottomBorder: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectionContainer.disabled(
              child: PostHeaderSection(
                post: post,
                topicId: widget.topicId,
                isTopicOwner: widget.isTopicOwner,
                showStamp: _acceptedAnswer,
                padding: EdgeInsets.zero,
                onJumpToPost: widget.onJumpToPost,
              ),
            ),
            const SizedBox(height: 12),
            if (post.notice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SelectionContainer.disabled(
                  child: PostNoticeWidget(
                    notice: post.notice!,
                    username: post.username,
                  ),
                ),
              ),
            Container(
              decoration: isModeratorAction
                  ? BoxDecoration(
                      color: theme.colorScheme.tertiaryContainer.withValues(
                        alpha: 0.2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    )
                  : null,
              padding: isModeratorAction
                  ? const EdgeInsets.all(12)
                  : EdgeInsets.zero,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) =>
                    CodeSelectionContextTracker.instance.clear(),
                child: ChunkedHtmlContent(
                  html: post.cooked,
                  textStyle: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                    fontSize:
                        (theme.textTheme.bodyMedium?.fontSize ?? 14) *
                        ref.watch(preferencesProvider).contentFontScale,
                  ),
                  linkCounts: post.linkCounts,
                  mentionedUsers: post.mentionedUsers,
                  searchHighlightQuery: widget.searchHighlightQuery,
                  post: post,
                  topicId: widget.topicId,
                  onQuoteImage: widget.onQuoteImage,
                  onInternalLinkTap: (topicId, topicSlug, postNumber) {
                    openInternalTopicLink(
                      context,
                      currentTopicId: widget.topicId,
                      targetTopicId: topicId,
                      topicSlug: topicSlug,
                      postNumber: postNumber,
                      onJumpToPost: widget.onJumpToPost,
                    );
                  },
                  onSelectionChanged: widget.onQuoteSelection != null
                      ? (content) {
                          _lastSelectedContent = content;
                          _lastCodeSelectionContext = content == null
                              ? null
                              : CodeSelectionContextTracker.instance.current;
                        }
                      : null,
                  contextMenuBuilder: widget.onQuoteSelection != null
                      ? (context, state) {
                          final items = QuoteSelectionHelper.buildMenuItems(
                            baseItems: state.contextMenuButtonItems,
                            plainText: _lastSelectedContent?.plainText,
                            post: post,
                            hideToolbar: state.hideToolbar,
                            topicId: widget.topicId,
                            onQuoteSelection: widget.onQuoteSelection,
                            codeContext: _lastCodeSelectionContext,
                          );
                          return AdaptiveTextSelectionToolbar.buttonItems(
                            anchors: state.contextMenuAnchors,
                            buttonItems: items,
                          );
                        }
                      : null,
                ),
              ),
            ),
            PostSignature(post: post),
            if (_acceptedAnswer)
              const SelectionContainer.disabled(
                child: AcceptedSolutionMarker(),
              ),
            // 举报隐藏帖子：显示展开按钮
            if (post.cookedHidden &&
                post.canSeeHiddenPost &&
                widget.onExpandHiddenPost != null)
              SelectionContainer.disabled(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: InkWell(
                    onTap: () => widget.onExpandHiddenPost!(post.id),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.visibility_outlined,
                            size: 15,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            context.l10n.post_viewHiddenInfo,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            SelectionContainer.disabled(
              child: PostFooterSection(
                post: post,
                topicId: widget.topicId,
                topicHasAcceptedAnswer: widget.topicHasAcceptedAnswer,
                acceptedAnswers: widget.acceptedAnswers,
                padding: const EdgeInsets.only(top: 12),
                highlightBoostUsername: widget.highlightBoostUsername,
                onReply: widget.onReply,
                onReplyWithInitialContent: widget.onReplyWithInitialContent,
                onEdit: widget.onEdit,
                onShareAsImage: widget.onShareAsImage,
                onRefreshPost: widget.onRefreshPost,
                onJumpToPost: widget.onJumpToPost,
                onSolutionChanged: widget.onSolutionChanged,
                useReplyDialog: widget.useReplyDialog,
                onShowPostDetail: widget.onShowPostDetail,
                hideRepliesButton: widget.hideRepliesButton,
                inlineRepliesState: widget.inlineRepliesState,
                onInlineRepliesStateChanged: widget.onInlineRepliesStateChanged,
                onAcceptedAnswerChanged: (accepted) {
                  if (!mounted) return;
                  setState(() {
                    _acceptedAnswer = accepted;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
