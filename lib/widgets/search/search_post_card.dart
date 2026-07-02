import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/search_result.dart';
import '../../models/topic.dart';
import '../../providers/home_topic_excerpt_provider.dart';
import '../../providers/preferences_provider.dart';
import '../../utils/html_excerpt.dart';
import '../topic/topic_card.dart';

String? searchPostPreviewHtml(SearchPost post) {
  final blurb = post.blurb.trim();
  return blurb.isEmpty ? null : post.blurb;
}

String? searchPostDetailFallbackHtml(SearchPost post) {
  if (post.postNumber != 1) return null;
  return searchPostPreviewHtml(post);
}

Topic searchPostToTopicPreview(
  SearchPost post, {
  String? excerptHtml,
  bool allowBlurbFallback = true,
}) {
  final searchTopic = post.topic;
  final title = searchTopic?.title ?? '';
  final slug = searchTopic?.slug ?? '';
  final postsCount = searchTopic?.postsCount ?? 1;
  final categoryId = searchTopic?.categoryId?.toString() ?? '0';
  final createdAt = post.createdAt;

  return Topic(
    id: searchTopic?.id ?? post.id,
    title: title,
    slug: slug,
    postsCount: postsCount,
    replyCount: (postsCount - 1).clamp(0, 999999).toInt(),
    views: searchTopic?.views ?? 0,
    likeCount: post.likeCount,
    excerpt: excerptHtml ?? (allowBlurbFallback ? searchPostPreviewHtml(post) : null),
    createdAt: createdAt,
    lastPostedAt: createdAt,
    lastPosterUsername: post.username,
    categoryId: categoryId,
    closed: searchTopic?.closed ?? false,
    archived: searchTopic?.archived ?? false,
    tags: searchTopic?.tags ?? const <Tag>[],
    posters: [
      TopicPoster(
        userId: post.id,
        description: 'Original Poster',
        extras: 'latest',
        user: TopicUser(
          id: post.id,
          username: post.username,
          avatarTemplate: post.avatarTemplate,
        ),
      ),
    ],
  );
}

class SearchTopicDetailPreview {
  const SearchTopicDetailPreview({
    required this.topic,
    required this.firstPostHtml,
  });

  final Topic topic;
  final String? firstPostHtml;
}

Future<SearchTopicDetailPreview> resolveSearchTopicDetailPreview({
  required HomeTopicExcerptLoader loader,
  required SearchPost post,
  Duration waitForFirstPost = const Duration(milliseconds: 250),
}) async {
  final searchTopic = post.topic;
  String? firstPostHtml;
  if (searchTopic != null) {
    firstPostHtml = loader.peekCached(searchTopic.id);
    final needsFetch = firstPostHtml == null || firstPostHtml.trim().isEmpty;
    if (needsFetch) {
      firstPostHtml = await loader.load(searchTopic.id).timeout(
        waitForFirstPost,
        onTimeout: () => null,
      );
    }
  }

  final fallbackHtml = searchPostDetailFallbackHtml(post);
  final previewHtml = (firstPostHtml?.trim().isNotEmpty ?? false)
      ? firstPostHtml
      : fallbackHtml;

  return SearchTopicDetailPreview(
    topic: searchPostToTopicPreview(
      post,
      excerptHtml: previewHtml,
      allowBlurbFallback: false,
    ),
    firstPostHtml: previewHtml,
  );
}

/// 搜索结果帖子卡片 — 复用首页话题卡片，避免搜索样式和首页漂移。
class SearchPostCard extends ConsumerWidget {
  final SearchPost post;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const SearchPostCard({
    super.key,
    required this.post,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentFontScale = ref.watch(
      preferencesProvider.select((p) => p.contentFontScale),
    );

    return TopicCard(
      topic: searchPostToTopicPreview(post),
      onTap: onTap,
      onLongPress: onLongPress,
      bottomWidget: post.blurb.isEmpty
          ? null
          : _buildBlurb(Theme.of(context), contentFontScale),
    );
  }

  Widget _buildBlurb(ThemeData theme, double contentFontScale) {
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
      height: 1.35,
      fontSize: (theme.textTheme.bodySmall?.fontSize ?? 12) * contentFontScale,
    );
    final normalizedBlurb = post.blurb.replaceAll('&hellip;', '...');
    final regex = RegExp(r'<span class="search-highlight">(.*?)</span>');
    final matches = regex.allMatches(normalizedBlurb);

    if (matches.isEmpty) {
      return SizedBox(
        width: double.infinity,
        child: Text(
          cleanHtmlExcerpt(normalizedBlurb),
          style: style,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    final spans = <TextSpan>[];
    int lastEnd = 0;

    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: _decodeInlineHtml(
              normalizedBlurb.substring(lastEnd, match.start),
            ),
          ),
        );
      }
      spans.add(
        TextSpan(
          text: match.group(1) ?? '',
          style: TextStyle(
            backgroundColor: theme.colorScheme.primaryContainer,
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
      lastEnd = match.end;
    }

    if (lastEnd < normalizedBlurb.length) {
      spans.add(
        TextSpan(text: _decodeInlineHtml(normalizedBlurb.substring(lastEnd))),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: RichText(
        text: TextSpan(style: style, children: spans),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  String _decodeInlineHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }
}
