import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/s.dart';
import '../../providers/discourse_providers.dart';
import '../notification/notification_quick_panel.dart';
import 'glass_icon_button.dart';

class NotificationIconButton extends ConsumerWidget {
  const NotificationIconButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    return GlassIconButton(
      onPressed: () {
        NotificationQuickPanel.show(context);
      },
      tooltip: context.l10n.common_notification,
      size: 40,
      iconSize: 20,
      borderRadius: 14,
      child: Badge(
        isLabelVisible: unreadCount > 0,
        label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
