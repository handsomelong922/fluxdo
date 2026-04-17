import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../providers/preferences_provider.dart';
import '../settings_model.dart';

/// 阅读设置数据声明
List<SettingsGroup> buildReadingGroups(BuildContext context) {
  final l10n = context.l10n;
  return [
    SettingsGroup(
      title: l10n.appearance_reading,
      icon: Icons.chrome_reader_mode_outlined,
      items: [
        DoubleSliderModel(
          id: 'contentFontScale',
          title: l10n.appearance_contentFontSize,
          icon: Icons.format_size_rounded,
          min: 0.8,
          max: 1.4,
          divisions: 12,
          labelBuilder: (v) => '${(v * 100).round()}%',
          getValue: (ref) => ref.watch(preferencesProvider).contentFontScale,
          onChanged: (ref, v) =>
              ref.read(preferencesProvider.notifier).setContentFontScale(v),
          onReset: (ref) =>
              ref.read(preferencesProvider.notifier).setContentFontScale(1.0),
        ),
        SwitchModel(
          id: 'displayPanguSpacing',
          title: l10n.appearance_panguSpacing,
          subtitle: l10n.appearance_panguSpacingDesc,
          icon: Icons.auto_fix_high_rounded,
          getValue: (ref) => ref.watch(preferencesProvider).displayPanguSpacing,
          onChanged: (ref, v) =>
              ref.read(preferencesProvider.notifier).setDisplayPanguSpacing(v),
        ),
      ],
    ),
    SettingsGroup(
      title: l10n.preferences_basic,
      icon: Icons.touch_app_outlined,
      items: [
        SwitchModel(
          id: 'longPressPreview',
          title: l10n.preferences_longPressPreview,
          subtitle: l10n.preferences_longPressPreviewDesc,
          icon: Icons.touch_app_rounded,
          getValue: (ref) => ref.watch(preferencesProvider).longPressPreview,
          onChanged: (ref, v) =>
              ref.read(preferencesProvider.notifier).setLongPressPreview(v),
        ),
        SwitchModel(
          id: 'hideBarOnScroll',
          title: l10n.preferences_hideBarOnScroll,
          subtitle: l10n.preferences_hideBarOnScrollDesc,
          icon: Icons.swap_vert_rounded,
          getValue: (ref) => ref.watch(preferencesProvider).hideBarOnScroll,
          onChanged: (ref, v) =>
              ref.read(preferencesProvider.notifier).setHideBarOnScroll(v),
        ),
        SwitchModel(
          id: 'openExternalLinksInAppBrowser',
          title: l10n.preferences_openLinksInApp,
          subtitle: l10n.preferences_openLinksInAppDesc,
          icon: Icons.open_in_browser_rounded,
          getValue: (ref) => ref.watch(preferencesProvider).openExternalLinksInAppBrowser,
          onChanged: (ref, v) => ref
              .read(preferencesProvider.notifier)
              .setOpenExternalLinksInAppBrowser(v),
        ),
        SwitchModel(
          id: 'expandRelatedLinks',
          title: l10n.reading_expandRelatedLinks,
          subtitle: l10n.reading_expandRelatedLinksDesc,
          icon: Icons.link_rounded,
          getValue: (ref) => ref.watch(preferencesProvider).expandRelatedLinks,
          onChanged: (ref, v) =>
              ref.read(preferencesProvider.notifier).setExpandRelatedLinks(v),
        ),
        PlatformConditionalModel(
          inner: SwitchModel(
            id: 'aiSwipeEntry',
            title: l10n.reading_aiSwipeEntry,
            subtitle: l10n.reading_aiSwipeEntryDesc,
            icon: Icons.swipe_left_rounded,
            getValue: (ref) => ref.watch(preferencesProvider).aiSwipeEntry,
            onChanged: (ref, v) =>
                ref.read(preferencesProvider.notifier).setAiSwipeEntry(v),
          ),
          condition: () => Platform.isIOS || Platform.isAndroid,
        ),
      ],
    ),
  ];
}
