import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/s.dart';
import '../../models/shortcut_binding.dart';
import '../../providers/shortcut_provider.dart';
import '../../utils/dialog_utils.dart';
import '../settings_model.dart';

/// 快捷键设置数据声明
List<SettingsGroup> buildShortcutGroups(BuildContext context) {
  final l10n = context.l10n;

  return [
    SettingsGroup(
      title: l10n.shortcuts_navigation,
      icon: Icons.navigation_rounded,
      items: [
        _shortcutCustomModel(ShortcutAction.navigateBack, l10n),
        _shortcutCustomModel(ShortcutAction.navigateBackAlt, l10n),
        _shortcutCustomModel(ShortcutAction.openSearch, l10n),
        _shortcutCustomModel(ShortcutAction.openSettings, l10n),
        _shortcutCustomModel(ShortcutAction.toggleNotifications, l10n),
        _shortcutCustomModel(ShortcutAction.switchToTopics, l10n),
        _shortcutCustomModel(ShortcutAction.switchToProfile, l10n),
        _shortcutCustomModel(ShortcutAction.previousTab, l10n),
        _shortcutCustomModel(ShortcutAction.nextTab, l10n),
        _shortcutCustomModel(ShortcutAction.switchPane, l10n),
      ],
    ),
    SettingsGroup(
      title: l10n.shortcuts_content,
      icon: Icons.article_rounded,
      items: [
        _shortcutCustomModel(ShortcutAction.closeOverlay, l10n),
        _shortcutCustomModel(ShortcutAction.refresh, l10n),
        _shortcutCustomModel(ShortcutAction.createTopic, l10n),
        _shortcutCustomModel(ShortcutAction.nextItem, l10n),
        _shortcutCustomModel(ShortcutAction.previousItem, l10n),
        _shortcutCustomModel(ShortcutAction.openItem, l10n),
        _shortcutCustomModel(ShortcutAction.toggleAiPanel, l10n),
        _shortcutCustomModel(ShortcutAction.showShortcutHelp, l10n),
      ],
    ),
  ];
}

CustomModel _shortcutCustomModel(ShortcutAction action, AppLocalizations l10n) {
  final label = _actionLabel(action, l10n);
  return CustomModel(
    id: 'shortcut_${action.name}',
    title: label,
    builder: (context, ref) => _ShortcutTile(action: action, label: label),
  );
}

class _ShortcutTile extends ConsumerWidget {
  final ShortcutAction action;
  final String label;

  const _ShortcutTile({required this.action, required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bindings = ref.watch(shortcutProvider);
    final binding = bindings.firstWhere((b) => b.action == action);
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(
        Icons.keyboard_rounded,
        color: binding.isCustomized
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
        size: 22,
      ),
      title: Text(label, style: theme.textTheme.bodyMedium),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              ShortcutBinding.formatActivator(binding.activator),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right_rounded,
            color: theme.colorScheme.outline.withValues(alpha: 0.4),
            size: 18,
          ),
        ],
      ),
      onTap: () => _showRecordKeyDialog(context, ref, binding),
    );
  }

  void _showRecordKeyDialog(
      BuildContext context, WidgetRef ref, ShortcutBinding binding) {
    showAppDialog(
      context: context,
      builder: (dialogContext) =>
          _RecordKeyDialog(binding: binding, parentRef: ref),
    );
  }
}

/// 录键对话框
class _RecordKeyDialog extends StatefulWidget {
  final ShortcutBinding binding;
  final WidgetRef parentRef;

  const _RecordKeyDialog({required this.binding, required this.parentRef});

  @override
  State<_RecordKeyDialog> createState() => _RecordKeyDialogState();
}

class _RecordKeyDialogState extends State<_RecordKeyDialog> {
  SingleActivator? _recorded;
  ShortcutAction? _conflict;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: AlertDialog(
        title: Text(_actionLabel(widget.binding.action, l10n)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 当前/录入的按键显示
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _conflict != null
                      ? theme.colorScheme.error.withValues(alpha: 0.5)
                      : theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  _recorded != null
                      ? ShortcutBinding.formatActivator(_recorded!)
                      : l10n.shortcuts_recordKey,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFamily: _recorded != null ? 'monospace' : null,
                    color: _recorded != null
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            // 冲突提示
            if (_conflict != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: theme.colorScheme.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.shortcuts_conflict(
                          _actionLabel(_conflict!, l10n)),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          // 恢复默认
          TextButton(
            onPressed: () async {
              await widget.parentRef
                  .read(shortcutProvider.notifier)
                  .resetBinding(widget.binding.action);
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(l10n.shortcuts_resetOne),
          ),
          // 取消
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.common_cancel),
          ),
          // 确认
          FilledButton(
            onPressed: _recorded != null && _conflict == null
                ? () async {
                    await widget.parentRef
                        .read(shortcutProvider.notifier)
                        .updateBinding(widget.binding.action, _recorded!);
                    if (context.mounted) Navigator.pop(context);
                  }
                : null,
            child: Text(l10n.common_confirm),
          ),
        ],
      ),
    );
  }

  void _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;

    // 忽略单独的修饰键
    if (_isModifierKey(key)) return;

    final activator = SingleActivator(
      key,
      control: HardwareKeyboard.instance.isControlPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
      alt: HardwareKeyboard.instance.isAltPressed,
      meta: HardwareKeyboard.instance.isMetaPressed,
    );

    // 检查冲突
    final conflict = widget.parentRef
        .read(shortcutProvider.notifier)
        .findConflict(activator, excludeAction: widget.binding.action);

    setState(() {
      _recorded = activator;
      _conflict = conflict;
    });
  }

  bool _isModifierKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight;
  }
}

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
