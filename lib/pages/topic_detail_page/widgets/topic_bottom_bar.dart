import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../l10n/s.dart';
import '../../../widgets/common/dismissible_popup_menu.dart';

/// 话题详情页底部操作栏
class TopicBottomBar extends StatelessWidget {
  final VoidCallback? onScrollToTop;
  final VoidCallback? onShare;
  final VoidCallback? onShareAsImage;
  final VoidCallback? onExport;
  final VoidCallback? onBookmark;
  final VoidCallback? onBookmarkLongPress;
  final bool hasSummary;
  final bool isBookmarked;
  final bool isSummaryMode;
  final bool isAuthorOnlyMode;
  final bool isTopLevelMode;
  final bool isLoading;
  final VoidCallback? onShowTopReplies;
  final VoidCallback? onShowAuthorOnly;
  final VoidCallback? onShowTopLevelReplies;
  final VoidCallback? onCancelFilter;
  final bool isPrivateMessage;

  const TopicBottomBar({
    super.key,
    this.onScrollToTop,
    this.onShare,
    this.onShareAsImage,
    this.onExport,
    this.onBookmark,
    this.onBookmarkLongPress,
    this.hasSummary = false,
    this.isBookmarked = false,
    this.isSummaryMode = false,
    this.isAuthorOnlyMode = false,
    this.isTopLevelMode = false,
    this.isLoading = false,
    this.isPrivateMessage = false,
    this.onShowTopReplies,
    this.onShowAuthorOnly,
    this.onShowTopLevelReplies,
    this.onCancelFilter,
  });

  bool get _hasActiveFilter =>
      isSummaryMode || isAuthorOnlyMode || isTopLevelMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isMobile =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final decoration = BoxDecoration(
      color: theme.colorScheme.surface.withValues(
        alpha: isMobile ? 0.96 : 0.76,
      ),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: theme.colorScheme.outlineVariant.withValues(
          alpha: isMobile ? 0.24 : 0.45,
        ),
      ),
      boxShadow: isMobile
          ? const <BoxShadow>[]
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
    );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: DecoratedBox(
          decoration: decoration,
          child: isMobile
              ? _buildBarContent(context, theme)
              : BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: _buildBarContent(context, theme),
                ),
        ),
      ),
    );
  }

  Widget _buildBarContent(BuildContext context, ThemeData theme) {
    return SizedBox(
      height: 56,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 6),
          _buildBookmarkButton(context, theme),
          if (_hasActiveFilter)
            _buildActiveFilterChip(context, theme)
          else
            _buildFilterMenuButton(context, theme),
          _buildShareMenu(context, theme),
          IconButton(
            onPressed: onScrollToTop,
            icon: const Icon(Icons.vertical_align_top),
            tooltip: context.l10n.topicDetail_scrollToTop,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _buildBookmarkButton(BuildContext context, ThemeData theme) {
    final label = isBookmarked
        ? context.l10n.topicDetail_editBookmark
        : context.l10n.common_addBookmark;
    return Semantics(
      button: true,
      label: label,
      child: SizedBox.square(
        dimension: 48,
        child: InkResponse(
          onTap: onBookmark,
          onLongPress: onBookmarkLongPress,
          radius: 24,
          child: Center(
            child: Icon(
              isBookmarked
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  /// 激活态：紧凑图标按钮 + 小关闭按钮
  Widget _buildActiveFilterChip(BuildContext context, ThemeData theme) {
    final (icon, _) = _activeFilterInfo(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: isLoading ? null : onCancelFilter,
          icon: Icon(icon, color: theme.colorScheme.primary),
          style: IconButton.styleFrom(
            backgroundColor: theme.colorScheme.primaryContainer,
          ),
          iconSize: 20,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  (IconData, String) _activeFilterInfo(BuildContext context) {
    if (isSummaryMode) {
      return (Icons.local_fire_department, context.l10n.topicDetail_hotOnly);
    }
    if (isAuthorOnlyMode) {
      return (Icons.person, context.l10n.topicDetail_authorOnly);
    }
    if (isTopLevelMode) {
      return (Icons.account_tree, context.l10n.topicDetail_topLevelOnly);
    }
    return (Icons.filter_list, '');
  }

  /// 未激活：筛选菜单按钮
  Widget _buildFilterMenuButton(BuildContext context, ThemeData theme) {
    return IconButton(
      onPressed: isLoading ? null : () => _showFilterMenu(context),
      icon: const Icon(Icons.filter_list),
      tooltip: context.l10n.topicDetail_filter,
    );
  }

  void _showFilterMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasSummary)
                ListTile(
                  leading: const Icon(Icons.local_fire_department_outlined),
                  title: Text(context.l10n.topicDetail_hotOnly),
                  onTap: () {
                    Navigator.pop(ctx);
                    onShowTopReplies?.call();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(context.l10n.topicDetail_authorOnly),
                onTap: () {
                  Navigator.pop(ctx);
                  onShowAuthorOnly?.call();
                },
              ),
              ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: Text(context.l10n.topicDetail_topLevelOnly),
                onTap: () {
                  Navigator.pop(ctx);
                  onShowTopLevelReplies?.call();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShareMenu(BuildContext context, ThemeData theme) {
    return SwipeDismissiblePopupMenuButton<String>(
      icon: const Icon(Icons.share_outlined),
      iconColor: theme.colorScheme.onSurfaceVariant,
      tooltip: context.l10n.common_share,
      onSelected: (value) {
        switch (value) {
          case 'link':
            onShare?.call();
            break;
          case 'image':
            onShareAsImage?.call();
            break;
          case 'export':
            onExport?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        // 私信话题不显示链接分享和生成分享图
        if (!isPrivateMessage)
          PopupMenuItem(
            value: 'link',
            child: Row(
              children: [
                Icon(Icons.link, size: 20, color: theme.colorScheme.onSurface),
                const SizedBox(width: 12),
                Text(context.l10n.topicDetail_shareLink),
              ],
            ),
          ),
        if (!isPrivateMessage)
          PopupMenuItem(
            value: 'image',
            child: Row(
              children: [
                Icon(
                  Icons.image_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurface,
                ),
                const SizedBox(width: 12),
                Text(context.l10n.topicDetail_generateShareImage),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'export',
          child: Row(
            children: [
              Icon(
                Icons.download_outlined,
                size: 20,
                color: theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 12),
              Text(context.l10n.topicDetail_exportArticle),
            ],
          ),
        ),
      ],
    );
  }
}
