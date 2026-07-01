import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/category.dart';
import '../../models/search_result.dart';
import '../../providers/category_provider.dart';
import '../../providers/preferences_provider.dart';
import '../../utils/font_awesome_helper.dart';
import '../../utils/html_excerpt.dart';
import '../../utils/number_utils.dart';
import '../../utils/platform_utils.dart';
import '../common/topic_badges.dart';
import '../common/relative_time_text.dart';
import '../common/smart_avatar.dart';

/// 搜索结果帖子卡片 — 对齐首页主帖卡片样式
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
    final theme = Theme.of(context);
    final topic = post.topic;
    final hideTopicListAvatars = ref.watch(
      preferencesProvider.select((p) => p.hideTopicListAvatars),
    );
    final contentFontScale = ref.watch(
      preferencesProvider.select((p) => p.contentFontScale),
    );

    // 获取分类信息
    final categoryMap = ref.watch(categoryMapProvider).value;
    final categoryId = topic?.categoryId;
    Category? category;
    if (categoryId != null && categoryMap != null) {
      category = categoryMap[categoryId];
    }

    // 图标逻辑：本级 FA Icon -> 本级 Logo -> 父级 FA Icon -> 父级 Logo
    IconData? faIcon = FontAwesomeHelper.getIcon(category?.icon);
    String? logoUrl = category?.uploadedLogo;

    if (faIcon == null &&
        (logoUrl == null || logoUrl.isEmpty) &&
        category?.parentCategoryId != null) {
      final parent = categoryMap?[category!.parentCategoryId];
      faIcon = FontAwesomeHelper.getIcon(parent?.icon);
      logoUrl = parent?.uploadedLogo;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTap: PlatformUtils.isDesktop ? onLongPress : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!hideTopicListAvatars) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _buildAvatar(),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTitleRow(theme, topic),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 24,
                      child: _buildBadgeLine(category, faIcon, logoUrl),
                    ),
                    if (post.blurb.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildBlurb(theme, contentFontScale),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _buildTrailingMeta(context, theme, topic),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return SmartAvatar(
      imageUrl: post.getAvatarUrl(size: 68),
      radius: 17,
      fallbackText: post.username,
    );
  }

  Widget _buildTitleRow(ThemeData theme, SearchTopic? topic) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildTopicTitle(post, topic, theme)),
        if (post.isAiGenerated || post.postNumber > 1) const SizedBox(width: 8),
        if (post.isAiGenerated)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.auto_awesome,
              size: 14,
              color: theme.colorScheme.tertiary,
            ),
          ),
        if (post.postNumber > 1)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '#${post.postNumber}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
                fontSize: 10,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBadgeLine(
    Category? category,
    IconData? faIcon,
    String? logoUrl,
  ) {
    return ClipRect(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(
          children: [
            if (category != null)
              CategoryBadge(
                category: category,
                faIcon: faIcon,
                logoUrl: logoUrl,
              ),
            if (category != null &&
                post.topic != null &&
                post.topic!.tags.isNotEmpty)
              const SizedBox(width: 6),
            if (post.topic != null) ..._buildTagBadges(post.topic!.tags),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTagBadges(List<dynamic> tags) {
    final widgets = <Widget>[];
    for (var i = 0; i < tags.take(4).length; i++) {
      if (i > 0) {
        widgets.add(const SizedBox(width: 6));
      }
      final tag = tags[i];
      widgets.add(TagBadge(name: tag.name));
    }
    return widgets;
  }

  Widget _buildTrailingMeta(
    BuildContext context,
    ThemeData theme,
    SearchTopic? topic,
  ) {
    final replyCount = topic == null
        ? 0
        : (topic.postsCount - 1).clamp(0, 999999);
    final showReply = replyCount > 0;
    final showLike = post.likeCount > 0;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 58, maxWidth: 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 18,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: RelativeTimeText(
                dateTime: post.createdAt,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
            ),
          ),
          if (showReply || showLike) ...[
            const SizedBox(height: 5),
            SizedBox(
              height: 18,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showReply)
                      _buildStat(
                        theme,
                        Icons.chat_bubble_outline_rounded,
                        replyCount,
                      ),
                    if (showReply && showLike) const SizedBox(width: 7),
                    if (showLike)
                      _buildStat(
                        theme,
                        Icons.favorite_border_rounded,
                        post.likeCount,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopicTitle(
    SearchPost post,
    SearchTopic? topic,
    ThemeData theme,
  ) {
    if (topic == null) return const SizedBox.shrink();

    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w500,
      height: 1.3,
    );

    // 如果有高亮标题，使用高亮版本
    if (post.topicTitleHeadline != null &&
        post.topicTitleHeadline!.isNotEmpty) {
      return _buildHighlightedTitle(
        post.topicTitleHeadline!,
        topic,
        theme,
        titleStyle,
      );
    }

    return Text.rich(
      TextSpan(
        style: titleStyle,
        children: [
          if (topic.closed)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (topic.archived)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.archive_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          TextSpan(text: topic.title),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 带状态图标的高亮标题
  Widget _buildHighlightedTitle(
    String headline,
    SearchTopic topic,
    ThemeData theme,
    TextStyle? style,
  ) {
    final spans = <InlineSpan>[];

    // 状态图标
    if (topic.closed) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              Icons.lock_outline,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    if (topic.archived) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              Icons.archive_outlined,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // 解析高亮文本
    final regex = RegExp(r'<span class="search-highlight">(.*?)</span>');
    final matches = regex.allMatches(headline);

    if (matches.isEmpty) {
      final cleanText = headline.replaceAll(RegExp(r'<[^>]*>'), '');
      spans.add(TextSpan(text: cleanText));
    } else {
      int lastEnd = 0;
      for (final match in matches) {
        if (match.start > lastEnd) {
          spans.add(
            TextSpan(
              text: headline
                  .substring(lastEnd, match.start)
                  .replaceAll(RegExp(r'<[^>]*>'), ''),
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
      if (lastEnd < headline.length) {
        spans.add(
          TextSpan(
            text: headline
                .substring(lastEnd)
                .replaceAll(RegExp(r'<[^>]*>'), ''),
          ),
        );
      }
    }

    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildStat(ThemeData theme, IconData icon, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          NumberUtils.formatCount(count),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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
      final cleanText = cleanHtmlExcerpt(normalizedBlurb);
      return Text(
        cleanText,
        style: style,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      );
    }

    final spans = <TextSpan>[];
    int lastEnd = 0;

    for (final match in matches) {
      if (match.start > lastEnd) {
        final beforeText = normalizedBlurb
            .substring(lastEnd, match.start)
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&quot;', '"')
            .replaceAll('&#39;', "'");
        spans.add(TextSpan(text: beforeText));
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
      final afterText = normalizedBlurb
          .substring(lastEnd)
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'");
      spans.add(TextSpan(text: afterText));
    }

    return RichText(
      text: TextSpan(style: style, children: spans),
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
    );
  }
}
