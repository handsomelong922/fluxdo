import 'dart:collection';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/topic.dart';
import '../../../providers/preferences_provider.dart';
import '../../../utils/topic_link_navigation.dart';
import '../../content/discourse_html_content/chunked/chunked_html_content.dart';
import '../../content/discourse_html_content/chunked/html_chunk.dart';
import '../../content/discourse_html_content/image_utils.dart';
import '../post_signature.dart';
import '../small_action_item.dart';
import 'widgets/post_footer_section/post_footer_section.dart';
import 'widgets/post_header_section.dart';
import 'widgets/post_segment_frame.dart';
import 'widgets/accepted_solution_marker.dart';

class LongPostRenderData {
  static final int _maxCacheEntries = Platform.isAndroid || Platform.isIOS
      ? 16
      : 128;
  static final LinkedHashMap<(int, int), LongPostRenderData> _cache =
      LinkedHashMap<(int, int), LongPostRenderData>();

  final List<HtmlChunk> chunks;
  final List<String> galleryImages;
  final Set<String> spoilerImageUrls;
  final Set<String> revealedImageUrls;

  LongPostRenderData({
    required this.chunks,
    required this.galleryImages,
    required this.spoilerImageUrls,
    Set<String>? revealedImageUrls,
  }) : revealedImageUrls = revealedImageUrls ?? <String>{};

  factory LongPostRenderData.fromHtml(String html) {
    final cacheKey = (html.hashCode, html.length);
    final cached = _cache.remove(cacheKey);
    if (cached != null) {
      _cache[cacheKey] = cached;
      return cached;
    }

    final chunks = ChunkedHtmlContent.getChunks(html) ?? const <HtmlChunk>[];
    if (chunks.isEmpty) {
      final renderData = LongPostRenderData(
        chunks: chunks,
        galleryImages: const <String>[],
        spoilerImageUrls: <String>{},
      );
      _cacheRenderData(cacheKey, renderData);
      return renderData;
    }

    final galleryInfo = GalleryInfo.fromHtml(html);
    final renderData = LongPostRenderData(
      chunks: chunks,
      galleryImages: galleryInfo.images,
      spoilerImageUrls: galleryInfo.spoilerImageUrls,
    );
    _cacheRenderData(cacheKey, renderData);
    return renderData;
  }

  static void clearCache() {
    _cache.clear();
  }

  static void _cacheRenderData(
    (int, int) cacheKey,
    LongPostRenderData renderData,
  ) {
    while (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[cacheKey] = renderData;
  }
}

class LongPostHeaderSegment extends StatelessWidget {
  final Post post;
  final int topicId;
  final bool highlight;
  final bool isTopicOwner;
  final String? dateSeparatorLabel;
  final bool showDivider;
  final void Function(int postNumber)? onJumpToPost;
  final bool useUsernameAsPrimaryLabel;

  const LongPostHeaderSegment({
    super.key,
    required this.post,
    required this.topicId,
    required this.highlight,
    required this.isTopicOwner,
    required this.dateSeparatorLabel,
    required this.showDivider,
    required this.onJumpToPost,
    this.useUsernameAsPrimaryLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    return PostSegmentFrame(
      post: post,
      highlight: highlight,
      showTopDateSeparator: dateSeparatorLabel != null,
      topDateSeparatorLabel: dateSeparatorLabel,
      showDivider: showDivider,
      showBottomBorder: false,
      child: SelectionContainer.disabled(
        child: PostHeaderSection(
          post: post,
          topicId: topicId,
          isTopicOwner: isTopicOwner,
          showStamp: post.acceptedAnswer,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          onJumpToPost: onJumpToPost,
          useUsernameAsPrimaryLabel: useUsernameAsPrimaryLabel,
        ),
      ),
    );
  }
}

class LongPostChunkSegment extends ConsumerWidget {
  final Post post;
  final int topicId;
  final bool highlight;
  final HtmlChunk chunk;
  final LongPostRenderData renderData;
  final void Function(String quote, Post post)? onQuoteImage;
  final void Function(int postNumber)? onJumpToPost;
  final String? searchHighlightQuery;

  const LongPostChunkSegment({
    super.key,
    required this.post,
    required this.topicId,
    required this.highlight,
    required this.chunk,
    required this.renderData,
    required this.onQuoteImage,
    required this.onJumpToPost,
    this.searchHighlightQuery,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isModeratorAction = post.postType == PostTypes.moderatorAction;
    final contentTextStyle = theme.textTheme.bodyMedium?.copyWith(
      height: 1.5,
      fontSize:
          (theme.textTheme.bodyMedium?.fontSize ?? 14) *
          ref.watch(preferencesProvider).contentFontScale,
    );

    return PostSegmentFrame(
      post: post,
      highlight: highlight,
      showBottomBorder: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
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
          child: HtmlChunkWidget(
            chunk: chunk,
            textStyle: contentTextStyle,
            onInternalLinkTap:
                (targetTopicId, topicSlug, postNumber, {initialNestedView}) {
                  openInternalTopicLink(
                    context,
                    currentTopicId: topicId,
                    targetTopicId: targetTopicId,
                    topicSlug: topicSlug,
                    postNumber: postNumber,
                    onJumpToPost: onJumpToPost,
                    initialNestedView: initialNestedView,
                  );
                },
            linkCounts: post.linkCounts,
            galleryImages: renderData.galleryImages,
            spoilerImageUrls: renderData.spoilerImageUrls,
            revealedImageUrls: renderData.revealedImageUrls,
            mentionedUsers: post.mentionedUsers,
            fullHtml: post.cooked,
            post: post,
            topicId: topicId,
            enableSelectionArea: false,
            onQuoteImage: onQuoteImage,
            searchHighlightQuery: searchHighlightQuery,
          ),
        ),
      ),
    );
  }
}

class LongPostFooterSegment extends StatelessWidget {
  final Post post;
  final int topicId;
  final bool highlight;
  final bool topicHasAcceptedAnswer;
  final List<AcceptedAnswer> acceptedAnswers;
  final String? bottomDateSeparatorLabel;
  final VoidCallback? onReply;
  final void Function(String initialContent)? onReplyWithInitialContent;
  final VoidCallback? onEdit;
  final VoidCallback? onShareAsImage;
  final void Function(int postId)? onRefreshPost;
  final void Function(int postNumber)? onJumpToPost;
  final void Function(int postId, bool accepted)? onSolutionChanged;
  final bool useReplyDialog;
  final VoidCallback? onShowPostDetail;
  final String? highlightBoostUsername;
  final InlineRepliesState? inlineRepliesState;
  final ValueChanged<InlineRepliesState>? onInlineRepliesStateChanged;
  final bool sharedIssueVisible;
  final bool canCreateSharedIssue;
  final int sharedIssueCount;
  final bool userCreatedSharedIssue;
  final void Function(int count, bool userCreated)? onSharedIssueChanged;
  final bool autoLoadRepliesPaused;
  final ValueListenable<bool>? autoLoadRepliesPausedListenable;
  final Set<String> blockedUsernames;

  const LongPostFooterSegment({
    super.key,
    required this.post,
    required this.topicId,
    required this.highlight,
    this.highlightBoostUsername,
    required this.topicHasAcceptedAnswer,
    this.acceptedAnswers = const [],
    required this.bottomDateSeparatorLabel,
    required this.onReply,
    this.onReplyWithInitialContent,
    required this.onEdit,
    required this.onShareAsImage,
    required this.onRefreshPost,
    required this.onJumpToPost,
    required this.onSolutionChanged,
    this.useReplyDialog = false,
    this.onShowPostDetail,
    this.inlineRepliesState,
    this.onInlineRepliesStateChanged,
    this.sharedIssueVisible = false,
    this.canCreateSharedIssue = false,
    this.sharedIssueCount = 0,
    this.userCreatedSharedIssue = false,
    this.onSharedIssueChanged,
    this.autoLoadRepliesPaused = false,
    this.autoLoadRepliesPausedListenable,
    this.blockedUsernames = const <String>{},
  });

  @override
  Widget build(BuildContext context) {
    final isAcceptedAnswer =
        post.acceptedAnswer ||
        acceptedAnswers.any((answer) => answer.postNumber == post.postNumber);
    return PostSegmentFrame(
      post: post,
      highlight: highlight,
      showBottomDateSeparator: bottomDateSeparatorLabel != null,
      bottomDateSeparatorLabel: bottomDateSeparatorLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PostSignature(
            post: post,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          ),
          if (isAcceptedAnswer)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SelectionContainer.disabled(
                child: AcceptedSolutionMarker(),
              ),
            ),
          SelectionContainer.disabled(
            child: PostFooterSection(
              post: post,
              topicId: topicId,
              topicHasAcceptedAnswer: topicHasAcceptedAnswer,
              acceptedAnswers: acceptedAnswers,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              highlightBoostUsername: highlightBoostUsername,
              onReply: onReply,
              onReplyWithInitialContent: onReplyWithInitialContent,
              onEdit: onEdit,
              onShareAsImage: onShareAsImage,
              onRefreshPost: onRefreshPost,
              onJumpToPost: onJumpToPost,
              onSolutionChanged: onSolutionChanged,
              useReplyDialog: useReplyDialog,
              onShowPostDetail: onShowPostDetail,
              inlineRepliesState: inlineRepliesState,
              onInlineRepliesStateChanged: onInlineRepliesStateChanged,
              sharedIssueVisible: sharedIssueVisible,
              canCreateSharedIssue: canCreateSharedIssue,
              sharedIssueCount: sharedIssueCount,
              userCreatedSharedIssue: userCreatedSharedIssue,
              onSharedIssueChanged: onSharedIssueChanged,
              autoLoadRepliesPaused: autoLoadRepliesPaused,
              autoLoadRepliesPausedListenable: autoLoadRepliesPausedListenable,
              blockedUsernames: blockedUsernames,
            ),
          ),
        ],
      ),
    );
  }
}
