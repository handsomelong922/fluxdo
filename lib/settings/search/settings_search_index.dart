import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../pages/appearance_page.dart';
import '../../pages/bottom_nav_settings_page.dart';
import '../../pages/data_management_page.dart';
import '../../pages/ai_prompt_settings_page.dart'; // CUSTOM: AI Prompt Settings
import '../../pages/network_settings_page/network_settings_page.dart';
import '../../pages/preferences_page.dart';
import '../../pages/reading_settings_page.dart';
import '../../pages/shortcut_settings_page.dart';
import '../../pages/keyword_filter_page.dart'; // CUSTOM: Keyword Filter
import '../../pages/tag_filter_page.dart'; // CUSTOM: Tag Filter
import '../../pages/user_filter_page.dart'; // CUSTOM: User Filter
import '../../utils/platform_utils.dart';
import '../definitions/appearance_defs.dart';
import '../definitions/bottom_nav_defs.dart';
import '../definitions/data_management_defs.dart';
import '../definitions/network_defs.dart';
import '../definitions/preferences_defs.dart';
import '../definitions/reading_defs.dart';
import '../definitions/shortcut_defs.dart';
import '../settings_model.dart';

/// 搜索结果项
class SettingsSearchResult {
  final SettingsModel model;
  final String categoryName;
  final IconData categoryIcon;
  final Color categoryColor;

  /// 构建目标页面，支持高亮定位
  final Widget Function({String? highlightId}) pageBuilder;

  const SettingsSearchResult({
    required this.model,
    required this.categoryName,
    required this.categoryIcon,
    required this.categoryColor,
    required this.pageBuilder,
  });
}

/// 构建全局搜索索引
List<SettingsSearchResult> buildSearchIndex(BuildContext context) {
  final l10n = context.l10n;

  List<SettingsSearchResult> fromGroups(
    List<SettingsGroup> groups, {
    required String categoryName,
    required IconData categoryIcon,
    required Color categoryColor,
    required Widget Function({String? highlightId}) pageBuilder,
  }) {
    return groups
        .expand((g) => g.items)
        .where((item) {
          if (item is PlatformConditionalModel) return item.shouldShow;
          return true;
        })
        .map(
          (item) => SettingsSearchResult(
            model: item is PlatformConditionalModel ? item.inner : item,
            categoryName: categoryName,
            categoryIcon: categoryIcon,
            categoryColor: categoryColor,
            pageBuilder: pageBuilder,
          ),
        )
        .toList();
  }

  return [
    ...fromGroups(
      buildReadingGroups(context),
      categoryName: l10n.settings_reading,
      categoryIcon: Icons.auto_stories_rounded,
      categoryColor: Colors.deepOrange,
      pageBuilder: ({highlightId}) =>
          ReadingSettingsPage(highlightId: highlightId),
    ),
    ...fromGroups(
      buildPreferencesGroups(context),
      categoryName: l10n.settings_preferences,
      categoryIcon: Icons.tune_rounded,
      categoryColor: Colors.deepPurple,
      pageBuilder: ({highlightId}) => PreferencesPage(highlightId: highlightId),
    ),
    ...fromGroups(
      buildBottomNavGroups(context),
      categoryName: l10n.settings_bottomNav,
      categoryIcon: Icons.view_day_rounded,
      categoryColor: Colors.amber,
      pageBuilder: ({highlightId}) =>
          BottomNavSettingsPage(highlightId: highlightId),
    ),
    ...fromGroups(
      buildAppearanceGroups(context),
      categoryName: l10n.settings_appearance,
      categoryIcon: Icons.color_lens_rounded,
      categoryColor: Colors.teal,
      pageBuilder: ({highlightId}) => AppearancePage(highlightId: highlightId),
    ),
    ...fromGroups(
      buildNetworkGroups(context),
      categoryName: l10n.settings_network,
      categoryIcon: Icons.network_check_rounded,
      categoryColor: Colors.blueGrey,
      pageBuilder: ({highlightId}) =>
          NetworkSettingsPage(highlightId: highlightId),
    ),
    ...fromGroups(
      buildDataManagementGroups(context),
      categoryName: l10n.settings_dataManagement,
      categoryIcon: Icons.storage_rounded,
      categoryColor: Colors.brown,
      pageBuilder: ({highlightId}) =>
          DataManagementPage(highlightId: highlightId),
    ),
    // 快捷键（仅桌面端）
    if (PlatformUtils.isDesktop)
      ...fromGroups(
        buildShortcutGroups(context),
        categoryName: l10n.settings_shortcuts,
        categoryIcon: Icons.keyboard_rounded,
        categoryColor: Colors.cyan,
        pageBuilder: ({highlightId}) =>
            ShortcutSettingsPage(highlightId: highlightId),
      ),
    SettingsSearchResult(
      model: ActionModel(
        id: 'custom_keyword_filter',
        title: '关键词屏蔽',
        subtitle: '按标题正则隐藏帖子',
        icon: Icons.block_rounded,
        onTap: (context, ref) {},
      ),
      categoryName: '自定义功能',
      categoryIcon: Icons.block_rounded,
      categoryColor: Colors.redAccent,
      pageBuilder: ({highlightId}) => const KeywordFilterPage(),
    ),
    SettingsSearchResult(
      model: ActionModel(
        id: 'custom_tag_filter',
        title: '标签屏蔽',
        subtitle: '按标签隐藏帖子',
        icon: Icons.local_offer_outlined,
        onTap: (context, ref) {},
      ),
      categoryName: '自定义功能',
      categoryIcon: Icons.local_offer_outlined,
      categoryColor: Colors.orangeAccent,
      pageBuilder: ({highlightId}) => const TagFilterPage(),
    ),
    SettingsSearchResult(
      model: ActionModel(
        id: 'custom_user_filter',
        title: '用户屏蔽',
        subtitle: '隐藏指定用户发布的内容',
        icon: Icons.person_off_rounded,
        onTap: (context, ref) {},
      ),
      categoryName: '自定义功能',
      categoryIcon: Icons.person_off_rounded,
      categoryColor: Colors.red,
      pageBuilder: ({highlightId}) => const UserFilterPage(),
    ),
    SettingsSearchResult(
      model: ActionModel(
        id: 'custom_ai_prompt_settings',
        title: 'AI 提示词配置',
        subtitle: '配置 AI 总结、回复和标题生成 prompt',
        icon: Icons.smart_toy_rounded,
        onTap: (context, ref) {},
      ),
      categoryName: '自定义功能',
      categoryIcon: Icons.smart_toy_rounded,
      categoryColor: Colors.cyan,
      pageBuilder: ({highlightId}) => const AiPromptSettingsPage(),
    ),
  ];
}
