import 'package:flutter/material.dart';

enum ProgressGestureAction {
  none,
  openTimeline,
  scrollToTop,
  jumpToUnread,
  nextPost,
  previousPost,
  reply,
  share,
  shareImage,
  exportArticle,
  openInBrowser,
  bookmark,
  readLater,
  notification,
  filter,
  toggleNestedView,
  aiAssistant,
  readingSettings,
  search,
  refresh,
}

/// 进度悬浮条手势动作的元数据（图标 + 标签）。
({IconData icon, String label}) progressGestureActionMeta(
  BuildContext context,
  ProgressGestureAction action,
) {
  switch (action) {
    case ProgressGestureAction.none:
      return (icon: Icons.do_not_disturb_alt_outlined, label: '无');
    case ProgressGestureAction.openTimeline:
      return (icon: Icons.unfold_more_rounded, label: '打开时间线');
    case ProgressGestureAction.scrollToTop:
      return (icon: Icons.vertical_align_top_rounded, label: '回到顶部');
    case ProgressGestureAction.jumpToUnread:
      return (icon: Icons.mark_chat_unread_outlined, label: '跳到未读');
    case ProgressGestureAction.nextPost:
      return (icon: Icons.south_rounded, label: '下一帖');
    case ProgressGestureAction.previousPost:
      return (icon: Icons.north_rounded, label: '上一帖');
    case ProgressGestureAction.reply:
      return (icon: Icons.reply_rounded, label: '回复');
    case ProgressGestureAction.share:
      return (icon: Icons.link_rounded, label: '分享链接');
    case ProgressGestureAction.shareImage:
      return (icon: Icons.image_outlined, label: '分享图片');
    case ProgressGestureAction.exportArticle:
      return (icon: Icons.download_outlined, label: '导出文章');
    case ProgressGestureAction.openInBrowser:
      return (icon: Icons.language_rounded, label: '浏览器打开');
    case ProgressGestureAction.bookmark:
      return (icon: Icons.bookmark_border_rounded, label: '收藏');
    case ProgressGestureAction.readLater:
      return (icon: Icons.layers_outlined, label: '稍后阅读');
    case ProgressGestureAction.notification:
      return (icon: Icons.notifications_none_rounded, label: '通知设置');
    case ProgressGestureAction.filter:
      return (icon: Icons.filter_list_rounded, label: '筛选');
    case ProgressGestureAction.toggleNestedView:
      return (icon: Icons.account_tree_outlined, label: '切换树形');
    case ProgressGestureAction.aiAssistant:
      return (icon: Icons.auto_awesome_rounded, label: 'AI 助手');
    case ProgressGestureAction.readingSettings:
      return (icon: Icons.auto_stories_rounded, label: '阅读设置');
    case ProgressGestureAction.search:
      return (icon: Icons.search_rounded, label: '搜索本帖');
    case ProgressGestureAction.refresh:
      return (icon: Icons.refresh_rounded, label: '刷新');
  }
}
