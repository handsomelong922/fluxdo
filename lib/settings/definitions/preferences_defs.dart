import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../providers/preferences_provider.dart';
import '../../utils/dialog_utils.dart';
import '../../providers/sticker_provider.dart';
import '../../services/sticker_market_service.dart';
import '../settings_model.dart';

/// 功能设置数据声明
List<SettingsGroup> buildPreferencesGroups(BuildContext context) {
  final l10n = context.l10n;
  return [
    SettingsGroup(
      title: l10n.preferences_basic,
      icon: Icons.tune,
      items: [
        SwitchModel(
          id: 'anonymousShare',
          title: l10n.preferences_anonymousShare,
          subtitle: l10n.preferences_anonymousShareDesc,
          icon: Icons.visibility_off_rounded,
          getValue: (ref) => ref.watch(preferencesProvider).anonymousShare,
          onChanged: (ref, v) =>
              ref.read(preferencesProvider.notifier).setAnonymousShare(v),
        ),
        SwitchModel(
          id: 'autoFillLogin',
          title: l10n.preferences_autoFillLogin,
          subtitle: l10n.preferences_autoFillLoginDesc,
          icon: Icons.password_rounded,
          getValue: (ref) => ref.watch(preferencesProvider).autoFillLogin,
          onChanged: (ref, v) =>
              ref.read(preferencesProvider.notifier).setAutoFillLogin(v),
        ),
        CustomModel(
          id: 'keywordFilter',
          title: l10n.preferences_keywordFilter,
          subtitle: l10n.preferences_keywordFilterDesc,
          builder: (context, ref) => _KeywordFilterInputTile(
            title: l10n.preferences_keywordFilter,
            description: l10n.preferences_keywordFilterDesc,
            hintText: l10n.preferences_keywordFilterHint,
          ),
        ),
        SwitchModel(
          id: 'cfClearanceRefresh',
          title: l10n.preferences_cfClearanceRefresh,
          subtitle: l10n.preferences_cfClearanceRefreshDesc,
          icon: Icons.security_update_warning_rounded,
          getValue: (ref) => ref.watch(preferencesProvider).cfClearanceRefresh,
          onChanged: (ref, v) =>
              ref.read(preferencesProvider.notifier).setCfClearanceRefresh(v),
        ),
        if (Platform.isAndroid)
          SwitchModel(
            id: 'androidNativeCdp',
            title: l10n.preferences_androidNativeCdp,
            subtitle: l10n.preferences_androidNativeCdpDesc,
            icon: Icons.developer_board_rounded,
            getValue: (ref) => ref.watch(preferencesProvider).androidNativeCdp,
            onChanged: (ref, v) =>
                ref.read(preferencesProvider.notifier).setAndroidNativeCdp(v),
          ),
        PlatformConditionalModel(
          inner: SwitchModel(
            id: 'portraitLock',
            title: l10n.preferences_portraitLock,
            subtitle: l10n.preferences_portraitLockDesc,
            icon: Icons.screen_lock_portrait_rounded,
            getValue: (ref) => ref.watch(preferencesProvider).portraitLock,
            onChanged: (ref, v) =>
                ref.read(preferencesProvider.notifier).setPortraitLock(v),
          ),
          condition: () => Platform.isIOS || Platform.isAndroid,
        ),
      ],
    ),
    SettingsGroup(
      title: l10n.preferences_editor,
      icon: Icons.edit_note_rounded,
      items: [
        SwitchModel(
          id: 'autoPanguSpacing',
          title: l10n.preferences_autoPanguSpacing,
          subtitle: l10n.preferences_autoPanguSpacingDesc,
          icon: Icons.auto_fix_high_rounded,
          getValue: (ref) => ref.watch(preferencesProvider).autoPanguSpacing,
          onChanged: (ref, v) =>
              ref.read(preferencesProvider.notifier).setAutoPanguSpacing(v),
        ),
        ActionModel(
          id: 'stickerSource',
          title: l10n.preferences_stickerSource,
          icon: Icons.sticky_note_2_outlined,
          getDynamicSubtitle: (ref) =>
              ref.watch(stickerMarketServiceProvider).baseUrl,
          onTap: (context, ref) => _showStickerBaseUrlDialog(context, ref),
        ),
      ],
    ),
    if (Platform.isAndroid)
      SettingsGroup(
        title: l10n.preferences_advanced,
        icon: Icons.bug_report_outlined,
        items: [
          SwitchModel(
            id: 'crashlytics',
            title: l10n.preferences_crashlytics,
            subtitle: l10n.preferences_crashlyticsDesc,
            icon: Icons.bug_report_rounded,
            getValue: (ref) => ref.watch(preferencesProvider).crashlytics,
            onChanged: (ref, v) =>
                ref.read(preferencesProvider.notifier).setCrashlytics(v),
          ),
        ],
      ),
  ];
}

void _showStickerBaseUrlDialog(BuildContext context, WidgetRef ref) {
  final service = ref.read(stickerMarketServiceProvider);
  final controller = TextEditingController(text: service.baseUrl);

  showAppDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(context.l10n.preferences_stickerSource),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: context.l10n.preferences_enterUrl,
              border: const OutlineInputBorder(),
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
              child: Text(context.l10n.common_restoreDefault),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(context.l10n.common_cancel),
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
          child: Text(context.l10n.common_confirm),
        ),
      ],
    ),
  ).then((_) => controller.dispose());
}

class _KeywordFilterInputTile extends ConsumerStatefulWidget {
  final String title;
  final String description;
  final String hintText;

  const _KeywordFilterInputTile({
    required this.title,
    required this.description,
    required this.hintText,
  });

  @override
  ConsumerState<_KeywordFilterInputTile> createState() =>
      _KeywordFilterInputTileState();
}

class _KeywordFilterInputTileState
    extends ConsumerState<_KeywordFilterInputTile> {
  late final TextEditingController _controller;
  String _lastSavedValue = '';

  @override
  void initState() {
    super.initState();
    final value = ref.read(preferencesProvider).keywordFilterInput;
    _lastSavedValue = value;
    _controller = TextEditingController(text: value);
  }

  Future<void> _saveIfChanged() async {
    final raw = _controller.text;
    if (raw == _lastSavedValue) return;
    _lastSavedValue = raw;
    await ref.read(preferencesProvider.notifier).setKeywordFilterInput(raw);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = ref.watch(preferencesProvider).keywordFilterInput;
    if (latest != _lastSavedValue && latest != _controller.text) {
      _lastSavedValue = latest;
      _controller.text = latest;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.filter_alt_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  widget.title,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: widget.hintText,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onEditingComplete: _saveIfChanged,
            onTapOutside: (_) => unawaited(_saveIfChanged()),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    final raw = _controller.text;
    if (raw != _lastSavedValue) {
      // ignore: discarded_futures
      ref.read(preferencesProvider.notifier).setKeywordFilterInput(raw);
    }
    _controller.dispose();
    super.dispose();
  }
}
