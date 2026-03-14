import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/preferences_provider.dart';
import '../providers/sticker_provider.dart';
import '../services/sticker_market_service.dart';

class PreferencesPage extends ConsumerWidget {
  const PreferencesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final preferences = ref.watch(preferencesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('功能设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _buildSectionHeader(theme, '基础'),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('长按预览'),
                  subtitle: const Text('长按话题卡片快速预览内容'),
                  secondary: Icon(
                    Icons.touch_app_rounded,
                    color: preferences.longPressPreview
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  value: preferences.longPressPreview,
                  onChanged: (value) {
                    ref.read(preferencesProvider.notifier).setLongPressPreview(value);
                  },
                ),
                Divider(height: 1, indent: 56, color: theme.colorScheme.outlineVariant.withValues(alpha:0.3)),
                SwitchListTile(
                  title: const Text('滚动收起导航栏'),
                  subtitle: const Text('首页滚动时自动收起顶栏和底栏'),
                  secondary: Icon(
                    Icons.swap_vert_rounded,
                    color: preferences.hideBarOnScroll
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  value: preferences.hideBarOnScroll,
                  onChanged: (value) {
                    ref.read(preferencesProvider.notifier).setHideBarOnScroll(value);
                  },
                ),
                Divider(height: 1, indent: 56, color: theme.colorScheme.outlineVariant.withValues(alpha:0.3)),
                SwitchListTile(
                  title: const Text('外部链接使用内置浏览器'),
                  subtitle: const Text('贴内外部链接优先在应用内打开'),
                  secondary: Icon(
                    Icons.open_in_browser_rounded,
                    color: preferences.openExternalLinksInAppBrowser
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  value: preferences.openExternalLinksInAppBrowser,
                  onChanged: (value) {
                    ref
                        .read(preferencesProvider.notifier)
                        .setOpenExternalLinksInAppBrowser(value);
                  },
                ),
                Divider(height: 1, indent: 56, color: theme.colorScheme.outlineVariant.withValues(alpha:0.3)),
                SwitchListTile(
                  title: const Text('匿名分享'),
                  subtitle: const Text('分享链接时不附带个人用户标识'),
                  secondary: Icon(
                    Icons.visibility_off_rounded,
                    color: preferences.anonymousShare
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  value: preferences.anonymousShare,
                  onChanged: (value) {
                    ref.read(preferencesProvider.notifier).setAnonymousShare(value);
                  },
                ),
                Divider(height: 1, indent: 56, color: theme.colorScheme.outlineVariant.withValues(alpha:0.3)),
                SwitchListTile(
                  title: const Text('自动填充登录'),
                  subtitle: const Text('记住账号密码，登录时自动填充'),
                  secondary: Icon(
                    Icons.password_rounded,
                    color: preferences.autoFillLogin
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  value: preferences.autoFillLogin,
                  onChanged: (value) {
                    ref.read(preferencesProvider.notifier).setAutoFillLogin(value);
                  },
                ),
                if (Platform.isIOS || Platform.isAndroid) ...[
                  Divider(height: 1, indent: 56, color: theme.colorScheme.outlineVariant.withValues(alpha:0.3)),
                  SwitchListTile(
                    title: const Text('竖屏锁定'),
                    subtitle: const Text('锁定屏幕方向为竖屏'),
                    secondary: Icon(
                      Icons.screen_lock_portrait_rounded,
                      color: preferences.portraitLock
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    value: preferences.portraitLock,
                    onChanged: (value) {
                      ref.read(preferencesProvider.notifier).setPortraitLock(value);
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader(theme, '编辑器'),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('自动混排优化'),
                  subtitle: const Text('输入时自动插入中英文混排空格'),
                  secondary: Icon(
                    Icons.auto_fix_high_rounded,
                    color: preferences.autoPanguSpacing
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  value: preferences.autoPanguSpacing,
                  onChanged: (value) {
                    ref.read(preferencesProvider.notifier).setAutoPanguSpacing(value);
                  },
                ),
                Divider(height: 1, indent: 56, color: theme.colorScheme.outlineVariant.withValues(alpha:0.3)),
                ListTile(
                  leading: Icon(
                    Icons.sticky_note_2_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('表情包数据源'),
                  subtitle: Text(
                    ref.watch(stickerMarketServiceProvider).baseUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
                  onTap: () => _showStickerBaseUrlDialog(context, ref),
                ),
              ],
            ),
          ),
          if (Platform.isAndroid) ...[
            const SizedBox(height: 24),
            _buildSectionHeader(theme, '高级'),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: SwitchListTile(
                title: const Text('崩溃日志上报'),
                subtitle: const Text('发生崩溃时自动上报日志，帮助开发者定位问题'),
                secondary: Icon(
                  Icons.bug_report_rounded,
                  color: preferences.crashlytics
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                value: preferences.crashlytics,
                onChanged: (value) async {
                  if (value) {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('开启崩溃日志上报'),
                        content: const Text(
                          '开启后，应用崩溃时会将崩溃日志上传到 Firebase Crashlytics 服务，'
                          '用于帮助开发者定位和修复问题。\n\n'
                          '上报内容仅包含崩溃堆栈信息，不包含个人数据。',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('开启'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      ref.read(preferencesProvider.notifier).setCrashlytics(true);
                    }
                  } else {
                    ref.read(preferencesProvider.notifier).setCrashlytics(false);
                  }
                },
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showStickerBaseUrlDialog(BuildContext context, WidgetRef ref) {
    final service = ref.read(stickerMarketServiceProvider);
    final controller = TextEditingController(text: service.baseUrl);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('表情包数据源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '输入 URL',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  controller.text = StickerMarketService.defaultBaseUrl;
                },
                child: const Text('恢复默认'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                await service.setBaseUrl(url);
                ref.invalidate(stickerGroupsProvider);
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Row(
      children: [
        Icon(Icons.tune, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
