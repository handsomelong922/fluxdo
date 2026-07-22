import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../models/category.dart';
import '../../models/topic.dart';
import '../../pages/category_topics_page.dart';
import '../../pages/tag_topics_page.dart';
import '../../providers/discourse_providers.dart';
import '../../providers/home_topic_excerpt_provider.dart';
import '../../providers/preferences_provider.dart';
import '../../services/navigation/topic_detail_route.dart';
import '../../utils/dialog_utils.dart';
import '../../utils/font_awesome_helper.dart';
import '../../utils/number_utils.dart';
import '../../utils/tag_icon_list.dart';
import '../../utils/time_utils.dart';
import '../../utils/topic_detail_preview.dart';
import '../common/emoji_text.dart';
import '../common/loading_spinner.dart';
import '../common/smart_avatar.dart';
import '../common/topic_badges.dart';
import '../content/discourse_html_content/discourse_html_content.dart';

/// 预览弹窗中的操作项。
class PreviewAction {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const PreviewAction({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });
}

/// 话题预览弹窗。
class TopicPreviewDialog extends ConsumerStatefulWidget {
  static const previewWindowKey = ValueKey<String>('topic-preview-window');
  static const metadataDividerKey = ValueKey<String>(
    'topic-preview-metadata-divider',
  );
  static const double viewportHeightFactor = 0.85;
  static const double minViewportHeightFactor = 0.46;
  static const double minDialogHeight = 320;
  static const double maxMinDialogHeight = 420;
  static const Duration resizeDuration = Duration(milliseconds: 220);

  final Topic topic;
  final VoidCallback? onOpen;
  final List<PreviewAction>? actions;

  const TopicPreviewDialog({
    super.key,
    required this.topic,
    this.onOpen,
    this.actions,
  });

  @override
  ConsumerState<TopicPreviewDialog> createState() => _TopicPreviewDialogState();

  static Future<void> show(
    BuildContext context, {
    required Topic topic,
    VoidCallback? onOpen,
    List<PreviewAction>? actions,
    TopicPreviewTrigger trigger = TopicPreviewTrigger.longPress,
  }) {
    if (trigger == TopicPreviewTrigger.longPress) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }

    return showAppGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: S.current.common_closePreview,
      barrierColor: const Color(0x80000000),
      transitionDuration: const Duration(milliseconds: 150),
      blur: false,
      pageBuilder: (context, animation, secondaryAnimation) {
        return TopicPreviewDialog(
          topic: topic,
          onOpen: onOpen,
          actions: actions,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

class _TopicPreviewDialogState extends ConsumerState<TopicPreviewDialog> {
  TopicDetail? _previewDetail;
  String? _firstPostCooked;
  bool _isLoading = true;
  bool _loadFailed = false;

  Topic get topic => widget.topic;

  @override
  void initState() {
    super.initState();
    _loadFirstPost();
  }

  Future<void> _loadFirstPost() async {
    final loader = ref.read(homeTopicExcerptLoaderProvider);
    try {
      var detail = loader.peekCachedPreview(topic.id);
      var cooked = detail?.postStream.posts.firstOrNull?.cooked;

      if (cooked == null || cooked.trim().isEmpty) {
        try {
          cooked = await loader.load(topic.id);
        } finally {
          loader.release(topic.id);
        }
        detail = loader.peekCachedPreview(topic.id);
      }

      final normalized = cooked?.trim();
      if (detail == null && normalized != null && normalized.isNotEmpty) {
        detail = buildTopicDetailPreview(topic: topic, previewHtml: cooked!);
      }

      if (!mounted) return;
      setState(() {
        _previewDetail = detail;
        _firstPostCooked = normalized == null || normalized.isEmpty
            ? null
            : cooked;
        _isLoading = false;
        _loadFailed = _firstPostCooked == null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final safeHeight = media.size.height - media.padding.vertical;
    final maxDialogHeight =
        safeHeight * TopicPreviewDialog.viewportHeightFactor;
    final preferredMinDialogHeight =
        (safeHeight * TopicPreviewDialog.minViewportHeightFactor).clamp(
          TopicPreviewDialog.minDialogHeight,
          TopicPreviewDialog.maxMinDialogHeight,
        );
    final minDialogHeight = preferredMinDialogHeight.clamp(
      0.0,
      maxDialogHeight,
    );
    final dialogWidth = (media.size.width * 0.9).clamp(0.0, 500.0);

    final categoryMap = ref.watch(categoryMapProvider).value;
    final categoryId = int.tryParse(topic.categoryId);
    final category = categoryMap?[categoryId];
    IconData? faIcon = FontAwesomeHelper.getIcon(category?.icon);
    String? logoUrl = category?.uploadedLogo;

    if (faIcon == null &&
        (logoUrl == null || logoUrl.isEmpty) &&
        category?.parentCategoryId != null) {
      final parent = categoryMap?[category!.parentCategoryId];
      faIcon = FontAwesomeHelper.getIcon(parent?.icon);
      logoUrl = parent?.uploadedLogo;
    }

    final hasActions = widget.actions != null && widget.actions!.isNotEmpty;
    final maxCardHeight = hasActions ? maxDialogHeight * 0.69 : maxDialogHeight;
    final minCardHeight = hasActions
        ? (minDialogHeight * 0.64).clamp(0.0, maxCardHeight)
        : minDialogHeight.clamp(0.0, maxCardHeight);

    return SafeArea(
      child: Center(
        child: AnimatedSize(
          key: TopicPreviewDialog.previewWindowKey,
          duration: TopicPreviewDialog.resizeDuration,
          reverseDuration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          child: SizedBox(
            width: dialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: minCardHeight,
                    maxHeight: maxCardHeight,
                  ),
                  child: Material(
                    color: theme.colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.55,
                        ),
                        width: 0.7,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    elevation: 8,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          fit: FlexFit.loose,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: (minCardHeight - 52).clamp(
                                0.0,
                                maxCardHeight,
                              ),
                            ),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                10,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildTitle(context, theme),
                                  const SizedBox(height: 8),
                                  _buildAuthorInfo(context, theme),
                                  if (category != null ||
                                      topic.tags.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _buildCategoryAndTags(
                                      context,
                                      theme,
                                      category,
                                      faIcon,
                                      logoUrl,
                                    ),
                                  ],
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 9,
                                      bottom: 10,
                                    ),
                                    child: Divider(
                                      key:
                                          TopicPreviewDialog.metadataDividerKey,
                                      height: 0.5,
                                      thickness: 0.5,
                                      color: theme.colorScheme.outlineVariant
                                          .withValues(alpha: 0.4),
                                    ),
                                  ),
                                  _buildPostContent(context, theme),
                                ],
                              ),
                            ),
                          ),
                        ),
                        _buildFooter(context, theme),
                      ],
                    ),
                  ),
                ),
                if (hasActions) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: maxDialogHeight * 0.28,
                    ),
                    child: _buildCustomActions(context, theme),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPostContent(BuildContext context, ThemeData theme) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: LoadingSpinner(size: 24),
        ),
      );
    }

    if (_firstPostCooked case final cooked?
        when cooked.isNotEmpty && !_loadFailed) {
      final contentFontScale = ref.watch(
        preferencesProvider.select((p) => p.contentFontScale),
      );
      return DiscourseHtmlContent(
        html: cooked,
        compact: true,
        textStyle: theme.textTheme.bodyMedium?.copyWith(
          height: 1.45,
          fontSize:
              (theme.textTheme.bodyMedium?.fontSize ?? 14) * contentFontScale,
        ),
        onInternalLinkTap:
            (topicId, topicSlug, postNumber, {initialNestedView}) {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                buildTopicDetailRoute<void>(
                  topicId: topicId,
                  initialTitle: topicSlug,
                  scrollToPostNumber: postNumber,
                  initialNestedView: initialNestedView,
                ),
              );
            },
      );
    }

    final excerpt = topic.excerpt;
    if (excerpt != null && excerpt.trim().isNotEmpty) {
      return _buildExcerptFallback(theme, excerpt);
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          S.current.common_loadFailed,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildExcerptFallback(ThemeData theme, String excerpt) {
    final cleanExcerpt = excerpt
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&hellip;', '...')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .trim();
    if (cleanExcerpt.isEmpty) return const SizedBox.shrink();

    final contentFontScale = ref.watch(
      preferencesProvider.select((p) => p.contentFontScale),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        cleanExcerpt,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.5,
          fontSize:
              (theme.textTheme.bodyMedium?.fontSize ?? 14) * contentFontScale,
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context, ThemeData theme) {
    final style = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          if (topic.closed)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Icon(
                  Icons.lock_outline,
                  size: 17,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (topic.pinned)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Icon(
                  Icons.push_pin_rounded,
                  size: 17,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          if (topic.hasAcceptedAnswer)
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: EdgeInsets.only(right: 5),
                child: Icon(Icons.check_box, size: 17, color: Colors.green),
              ),
            ),
          ...EmojiText.buildEmojiSpans(context, topic.title, style),
        ],
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildAuthorInfo(BuildContext context, ThemeData theme) {
    final detailAuthor = _previewDetail?.createdBy;
    final listAuthor = topic.posters.firstOrNull?.user;
    final author = detailAuthor ?? listAuthor;
    final username = author?.username ?? topic.lastPosterUsername ?? '';
    final avatarUrl = author?.getAvatarUrl(size: 48);
    final createdAt = _previewDetail?.createdAt ?? topic.createdAt;

    return Row(
      children: [
        SmartAvatar(imageUrl: avatarUrl, radius: 12, fallbackText: username),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            username,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (createdAt != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Text(
              '·',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Flexible(
            child: Text(
              '${S.current.topic_createdAt} ${TimeUtils.formatRelativeTime(createdAt)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryAndTags(
    BuildContext context,
    ThemeData theme,
    Category? category,
    IconData? faIcon,
    String? logoUrl,
  ) {
    const badgeSize = BadgeSize.dense;
    final textStyle = theme.textTheme.labelSmall?.copyWith(fontSize: 9);
    final candidates = <({Widget child, double width})>[];

    if (category != null) {
      candidates.add((
        child: CategoryBadge(
          category: category,
          faIcon: faIcon,
          logoUrl: logoUrl,
          size: badgeSize,
          textStyle: textStyle?.copyWith(fontWeight: FontWeight.w500),
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CategoryTopicsPage(category: category),
              ),
            );
          },
        ),
        width: _measureBadgeText(context, category.name, textStyle) + 31,
      ));
    }

    for (final tag in topic.tags) {
      candidates.add((
        child: TagBadge(
          name: tag.name,
          size: badgeSize,
          textStyle: textStyle,
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TagTopicsPage(tagName: tag.name),
              ),
            );
          },
        ),
        width:
            _measureBadgeText(context, tag.name, textStyle) +
            (TagIconList.get(tag.name) == null ? 12 : 25),
      ));
    }

    return SizedBox(
      height: 22,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 5.0;
          const ellipsisWidth = 12.0;
          final visible = <Widget>[];
          var usedWidth = 0.0;
          var omitted = false;

          for (var index = 0; index < candidates.length; index++) {
            final candidate = candidates[index];
            final leadingGap = visible.isEmpty ? 0.0 : gap;
            final hasMore = index < candidates.length - 1;
            final reserved = hasMore ? gap + ellipsisWidth : 0.0;
            if (usedWidth + leadingGap + candidate.width + reserved >
                constraints.maxWidth) {
              omitted = true;
              break;
            }
            if (visible.isNotEmpty) visible.add(const SizedBox(width: gap));
            visible.add(candidate.child);
            usedWidth += leadingGap + candidate.width;
          }

          if (omitted &&
              usedWidth + gap + ellipsisWidth <= constraints.maxWidth) {
            if (visible.isNotEmpty) visible.add(const SizedBox(width: gap));
            visible.add(
              Text(
                '…',
                style: textStyle?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }

          return ClipRect(child: Row(children: visible));
        },
      ),
    );
  }

  double _measureBadgeText(
    BuildContext context,
    String text,
    TextStyle? style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }

  Widget _buildFooter(BuildContext context, ThemeData theme) {
    final detail = _previewDetail;
    final replyCount = ((detail?.postsCount ?? topic.postsCount) - 1)
        .clamp(0, 999999)
        .toInt();
    final views = detail?.views ?? topic.views;
    final likes = detail?.likeCount ?? topic.likeCount;
    final lastReply = TimeUtils.formatRelativeTime(topic.lastPostedAt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCompactStat(
                  context,
                  icon: Icons.chat_bubble_outline_rounded,
                  value: NumberUtils.formatCount(replyCount),
                  tooltip: S.current.topic_replyCount(replyCount),
                  alignment: Alignment.centerLeft,
                  iconSize: 18,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 22,
                  foregroundColor: theme.colorScheme.primary,
                ),
                const SizedBox(height: 3),
                _buildCompactStat(
                  context,
                  icon: Icons.visibility_outlined,
                  value: NumberUtils.formatCount(views),
                  tooltip: S.current.topic_viewCount(
                    NumberUtils.formatCount(views),
                  ),
                  alignment: Alignment.centerLeft,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: _openDetails,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(S.current.common_viewDetails),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildCompactStat(
                  context,
                  icon: Icons.favorite_border_rounded,
                  value: NumberUtils.formatCount(likes),
                  tooltip: S.current.topic_likeCount(
                    NumberUtils.formatCount(likes),
                  ),
                  alignment: Alignment.centerRight,
                ),
                const SizedBox(height: 3),
                _buildCompactStat(
                  context,
                  icon: Icons.access_time_rounded,
                  value: lastReply,
                  tooltip: '${S.current.topic_lastReply} $lastReply',
                  alignment: Alignment.centerRight,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactStat(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String tooltip,
    required Alignment alignment,
    double iconSize = 13,
    double fontSize = 10,
    FontWeight? fontWeight,
    double height = 16,
    Color? foregroundColor,
  }) {
    final theme = Theme.of(context);
    final color = foregroundColor ?? theme.colorScheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: iconSize, color: color),
              const SizedBox(width: 3),
              Text(
                value,
                maxLines: 1,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontSize: fontSize,
                  fontWeight: fontWeight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetails() {
    var detail = _previewDetail;
    final cooked = _firstPostCooked;
    if (detail == null && cooked != null && cooked.trim().isNotEmpty) {
      detail = buildTopicDetailPreview(topic: topic, previewHtml: cooked);
    }
    if (detail != null) {
      final username = ref.read(currentUserProvider).value?.username;
      ref
          .read(topicDetailCacheServiceProvider)
          .writePreviewSeed(detail, username: username);
    }

    final navigator = Navigator.of(context);
    navigator.pop();
    final onOpen = widget.onOpen;
    if (onOpen != null) {
      onOpen();
      return;
    }
    navigator.push(
      buildTopicDetailRoute<void>(
        topicId: topic.id,
        initialTitle: topic.title,
        scrollToPostNumber: cooked == null ? topic.lastReadPostNumber : null,
        initialTopicPreview: topic,
        initialFirstPostHtml: cooked,
      ),
    );
  }

  Widget _buildCustomActions(BuildContext context, ThemeData theme) {
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      elevation: 8,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: widget.actions!.asMap().entries.map((entry) {
            final index = entry.key;
            final action = entry.value;
            final color = action.color ?? theme.colorScheme.onSurface;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (index > 0)
                  Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.4,
                    ),
                  ),
                InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                    action.onTap();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(action.icon, size: 19, color: color),
                        const SizedBox(width: 10),
                        Text(
                          action.label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
