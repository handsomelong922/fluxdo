import 'package:flutter/material.dart';

/// 话题详情页底部操作栏
class TopicBottomBar extends StatelessWidget {
  final VoidCallback? onScrollToTop;
  final VoidCallback? onShare;
  final VoidCallback? onShareAsImage;
  final VoidCallback? onExport;
  final VoidCallback? onOpenInBrowser;
  final bool hasSummary;
  final bool isSummaryMode;
  final bool isAuthorOnlyMode;
  final bool isLoading;
  final VoidCallback? onShowTopReplies;
  final VoidCallback? onShowAuthorOnly;
  final VoidCallback? onCancelFilter;

  const TopicBottomBar({
    super.key,
    this.onScrollToTop,
    this.onShare,
    this.onShareAsImage,
    this.onExport,
    this.onOpenInBrowser,
    this.hasSummary = false,
    this.isSummaryMode = false,
    this.isAuthorOnlyMode = false,
    this.isLoading = false,
    this.onShowTopReplies,
    this.onShowAuthorOnly,
    this.onCancelFilter,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      height: 80,
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          // 回到顶部
          IconButton(
            onPressed: onScrollToTop,
            icon: const Icon(Icons.vertical_align_top),
            tooltip: '回到顶部',
          ),
          // 热门回复切换
          if (hasSummary)
            _buildTopRepliesButton(context),
          // 只看题主
          _buildAuthorOnlyButton(context),
          // 分享菜单
          _buildShareMenu(context, theme),
          // 在浏览器打开
          IconButton(
            onPressed: onOpenInBrowser,
            icon: const Icon(Icons.language),
            tooltip: '在浏览器打开',
          ),
        ],
      ),
    );
  }

  Widget _buildShareMenu(BuildContext context, ThemeData theme) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.share_outlined),
      iconColor: theme.colorScheme.onSurfaceVariant,
      tooltip: '分享',
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
        PopupMenuItem(
          value: 'link',
          child: Row(
            children: [
              Icon(
                Icons.link,
                size: 20,
                color: theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 12),
              const Text('分享链接'),
            ],
          ),
        ),
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
              const Text('生成分享图片'),
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
              const Text('导出文章'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopRepliesButton(BuildContext context) {
    final theme = Theme.of(context);

    return IconButton(
      onPressed: isLoading ? null : (isSummaryMode ? onCancelFilter : onShowTopReplies),
      icon: Icon(
        isSummaryMode
            ? Icons.local_fire_department
            : Icons.local_fire_department_outlined,
        color: isSummaryMode ? theme.colorScheme.primary : null,
      ),
      style: IconButton.styleFrom(
        backgroundColor: isSummaryMode ? theme.colorScheme.primaryContainer : null,
      ),
      tooltip: isSummaryMode ? '查看全部' : '只看热门',
    );
  }

  Widget _buildAuthorOnlyButton(BuildContext context) {
    final theme = Theme.of(context);

    return IconButton(
      onPressed: isLoading ? null : (isAuthorOnlyMode ? onCancelFilter : onShowAuthorOnly),
      icon: Icon(
        isAuthorOnlyMode
            ? Icons.person
            : Icons.person_outline,
        color: isAuthorOnlyMode ? theme.colorScheme.primary : null,
      ),
      style: IconButton.styleFrom(
        backgroundColor: isAuthorOnlyMode ? theme.colorScheme.primaryContainer : null,
      ),
      tooltip: isAuthorOnlyMode ? '查看全部' : '只看题主',
    );
  }
}
