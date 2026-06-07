import 'dart:ui';

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

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.70),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.36),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.22 : 0.10,
                  ),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SizedBox(
              height: 56,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 6),
                  // 回到顶部
                  _GlassToolIconButton(
                    onPressed: onScrollToTop,
                    icon: Icons.vertical_align_top_rounded,
                    tooltip: context.l10n.topicDetail_scrollToTop,
                  ),
                  // 筛选
                  if (_hasActiveFilter)
                    _buildActiveFilterChip(context, theme)
                  else
                    _buildFilterMenuButton(context, theme),
                  // 分享菜单
                  _buildShareMenu(context, theme),
                  // 添加/编辑书签
                  _buildBookmarkButton(context, theme),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBookmarkButton(BuildContext context, ThemeData theme) {
    final label = isBookmarked
        ? context.l10n.topicDetail_editBookmark
        : context.l10n.common_addBookmark;
    return _GlassToolIconButton(
      onPressed: onBookmark,
      onLongPress: onBookmarkLongPress,
      icon: isBookmarked
          ? Icons.bookmark_rounded
          : Icons.bookmark_border_rounded,
      tooltip: label,
      selected: isBookmarked,
    );
  }

  /// 激活态：紧凑图标按钮 + 小关闭按钮
  Widget _buildActiveFilterChip(BuildContext context, ThemeData theme) {
    final (icon, _) = _activeFilterInfo(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GlassToolIconButton(
          onPressed: isLoading ? null : onCancelFilter,
          icon: icon,
          tooltip: context.l10n.topicDetail_filter,
          selected: true,
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
    return _GlassToolIconButton(
      onPressed: isLoading ? null : () => _showFilterMenu(context),
      icon: Icons.filter_list_rounded,
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
      tooltip: context.l10n.common_share,
      child: _GlassToolIconButtonSurface(
        icon: Icons.ios_share_rounded,
        tooltip: context.l10n.common_share,
      ),
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

class _GlassToolIconButton extends StatelessWidget {
  const _GlassToolIconButton({
    required this.onPressed,
    required this.icon,
    required this.tooltip,
    this.onLongPress,
    this.selected = false,
  });

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final IconData icon;
  final String tooltip;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        enabled: onPressed != null,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onPressed,
          onLongPress: onLongPress,
          child: _GlassToolIconButtonSurface(
            icon: icon,
            tooltip: tooltip,
            selected: selected,
            enabled: onPressed != null,
          ),
        ),
      ),
    );
  }
}

class _GlassToolIconButtonSurface extends StatelessWidget {
  const _GlassToolIconButtonSurface({
    required this.icon,
    required this.tooltip,
    this.selected = false,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground = !enabled
        ? colorScheme.outline
        : selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return SizedBox.square(
      dimension: 44,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primaryContainer.withValues(alpha: 0.78),
                    colorScheme.primary.withValues(alpha: 0.18),
                  ],
                )
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                    colorScheme.surface.withValues(alpha: 0.18),
                  ],
                ),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.24)
                : colorScheme.outlineVariant.withValues(alpha: 0.24),
          ),
        ),
        child: Center(child: Icon(icon, size: 20, color: foreground)),
      ),
    );
  }
}
