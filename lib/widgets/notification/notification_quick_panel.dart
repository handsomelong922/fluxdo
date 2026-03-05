import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/discourse_providers.dart';
import '../../pages/notifications_page.dart';
import '../../utils/notification_navigation.dart';
import 'notification_item.dart';
import 'notification_list_skeleton.dart';

/// 通知快捷面板（BottomSheet）
/// 显示最近通知，由 recentNotificationsProvider 驱动
class NotificationQuickPanel extends ConsumerStatefulWidget {
  const NotificationQuickPanel({super.key});

  /// 弹出快捷面板
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NotificationQuickPanel(),
    );
  }

  @override
  ConsumerState<NotificationQuickPanel> createState() => _NotificationQuickPanelState();
}

class _NotificationQuickPanelState extends ConsumerState<NotificationQuickPanel> {
  @override
  void initState() {
    super.initState();
    // 每次打开面板时刷新
    Future.microtask(() {
      ref.invalidate(recentNotificationsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenHeight = MediaQuery.of(context).size.height;
    final notificationsAsync = ref.watch(recentNotificationsProvider);
    final systemAvatarTemplate = ref.watch(systemUserAvatarTemplateProvider).value;

    return Container(
      height: screenHeight * 0.8,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 拖拽手柄
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Row(
              children: [
                Text('通知', style: theme.textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  onPressed: () async {
                    await ref.read(recentNotificationsProvider.notifier).markAllAsRead();
                  },
                  icon: const Icon(Icons.done_all, size: 20),
                  tooltip: '全部标为已读',
                  style: IconButton.styleFrom(
                    foregroundColor: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationsPage()),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '查看全部',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 通知列表
          Expanded(
            child: notificationsAsync.when(
              data: (notifications) {
                if (notifications.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.notifications_none, size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('暂无通知', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom,
                  ),
                  itemCount: notifications.length,
                  itemBuilder: (context, index) {
                    final notification = notifications[index];
                    return NotificationItem(
                      notification: notification,
                      systemAvatarTemplate: systemAvatarTemplate,
                      onTap: () {
                        handleNotificationTap(context, ref, notification);
                      },
                    );
                  },
                );
              },
              loading: () => const NotificationListSkeleton(),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text('加载失败', style: TextStyle(color: colorScheme.error)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => ref.invalidate(recentNotificationsProvider),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
