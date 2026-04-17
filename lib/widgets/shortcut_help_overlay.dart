import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../l10n/s.dart';
import '../models/shortcut_binding.dart';
import '../providers/shortcut_provider.dart';

/// 显示快捷键帮助浮层，返回 Future 以便跟踪关闭时机
Future<void> showShortcutHelpOverlay(BuildContext context, WidgetRef ref) {
  final bindings = ref.read(shortcutProvider);

  return showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (context) => _ShortcutHelpDialog(bindings: bindings),
  );
}

class _ShortcutHelpDialog extends StatelessWidget {
  final List<ShortcutBinding> bindings;

  const _ShortcutHelpDialog({required this.bindings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    // 按分类分组
    final groups = <ShortcutCategory, List<ShortcutBinding>>{};
    for (final binding in bindings) {
      groups.putIfAbsent(binding.category, () => []).add(binding);
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题（固定）
              Row(
                children: [
                  Icon(Icons.keyboard_rounded,
                      color: theme.colorScheme.primary, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    l10n.settings_shortcuts,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(32, 32),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 内容（可滚动）
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final entry in groups.entries) ...[
                      _buildCategoryHeader(
                          theme, _categoryLabel(entry.key, l10n)),
                      const SizedBox(height: 8),
                      ...entry.value.map((b) => _buildShortcutRow(
                          theme, _actionLabel(b.action, l10n), b)),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),

              // 底部提示（固定）
              const SizedBox(height: 8),
              Text(
                l10n.shortcuts_customizeHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryHeader(ThemeData theme, String label) {
    return Text(
      label,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildShortcutRow(
      ThemeData theme, String label, ShortcutBinding binding) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          _KeyChip(
            label: ShortcutBinding.formatActivator(binding.activator),
            theme: theme,
          ),
        ],
      ),
    );
  }
}

/// 按键标签 Chip
class _KeyChip extends StatelessWidget {
  final String label;
  final ThemeData theme;

  const _KeyChip({required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w500,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

/// 获取分类显示名称
String _categoryLabel(ShortcutCategory category, AppLocalizations l10n) {
  return switch (category) {
    ShortcutCategory.navigation => l10n.shortcuts_navigation,
    ShortcutCategory.content => l10n.shortcuts_content,
  };
}

/// 获取动作显示名称
String _actionLabel(ShortcutAction action, AppLocalizations l10n) {
  return switch (action) {
    ShortcutAction.navigateBack => l10n.shortcuts_navigateBack,
    ShortcutAction.navigateBackAlt => l10n.shortcuts_navigateBackAlt,
    ShortcutAction.openSearch => l10n.shortcuts_openSearch,
    ShortcutAction.closeOverlay => l10n.shortcuts_closeOverlay,
    ShortcutAction.openSettings => l10n.shortcuts_openSettings,
    ShortcutAction.refresh => l10n.shortcuts_refresh,
    ShortcutAction.showShortcutHelp => l10n.shortcuts_showHelp,
    ShortcutAction.nextItem => l10n.shortcuts_nextItem,
    ShortcutAction.previousItem => l10n.shortcuts_previousItem,
    ShortcutAction.openItem => l10n.shortcuts_openItem,
    ShortcutAction.switchPane => l10n.shortcuts_switchPane,
    ShortcutAction.toggleNotifications => l10n.shortcuts_toggleNotifications,
    ShortcutAction.switchToTopics => l10n.shortcuts_switchToTopics,
    ShortcutAction.switchToProfile => l10n.shortcuts_switchToProfile,
    ShortcutAction.createTopic => l10n.shortcuts_createTopic,
    ShortcutAction.previousTab => l10n.shortcuts_previousTab,
    ShortcutAction.nextTab => l10n.shortcuts_nextTab,
    ShortcutAction.toggleAiPanel => l10n.shortcuts_toggleAiPanel,
  };
}
