import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../providers/preferences_provider.dart';
import '../../services/external_browser_service.dart';
import '../settings_model.dart';
import '../../navigation/page_transition_preferences.dart';
import '../../utils/dialog_utils.dart';

const _systemDefaultBrowserValue = '__system_default_browser__';

final availableExternalBrowsersProvider =
    FutureProvider<List<ExternalBrowserApp>>((ref) {
      return ExternalBrowserService.listAvailableBrowsers();
    });

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
          id: 'preferStaticAvatars',
          title: l10n.preferences_preferStaticAvatars,
          subtitle: l10n.preferences_preferStaticAvatarsDesc,
          icon: Icons.image_not_supported_outlined,
          getValue: (ref) => ref.watch(preferencesProvider).preferStaticAvatars,
          onChanged: (ref, v) =>
              ref.read(preferencesProvider.notifier).setPreferStaticAvatars(v),
        ),
        SwitchModel(
          id: 'hideTopicListAvatars',
          title: l10n.preferences_hideTopicListAvatars,
          subtitle: l10n.preferences_hideTopicListAvatarsDesc,
          icon: Icons.person_off_outlined,
          getValue: (ref) =>
              ref.watch(preferencesProvider).hideTopicListAvatars,
          onChanged: (ref, v) =>
              ref.read(preferencesProvider.notifier).setHideTopicListAvatars(v),
        ),
        SwitchModel(
          id: 'reduceLoadingAnimations',
          title: l10n.preferences_reduceLoadingAnimations,
          subtitle: l10n.preferences_reduceLoadingAnimationsDesc,
          icon: Icons.motion_photos_off_rounded,
          getValue: (ref) =>
              ref.watch(preferencesProvider).reduceLoadingAnimations,
          onChanged: (ref, v) => ref
              .read(preferencesProvider.notifier)
              .setReduceLoadingAnimations(v),
        ),
        ActionModel(
          id: 'pageTransition',
          title: l10n.preferences_pageTransition,
          subtitle: l10n.preferences_pageTransitionDesc,
          icon: Icons.animation_rounded,
          getDynamicSubtitle: (ref) => _pageTransitionLabel(
            context,
            ref.watch(preferencesProvider).pageTransition,
          ),
          onTap: (context, ref) => _showPageTransitionPicker(context, ref),
        ),
        SwitchModel(
          id: 'defaultNestedTopicView',
          title: l10n.nested_title,
          subtitle: '进入帖子时默认使用树形视图',
          icon: Icons.forum_outlined,
          getValue: (ref) =>
              ref.watch(preferencesProvider).defaultNestedTopicView,
          onChanged: (ref, v) => ref
              .read(preferencesProvider.notifier)
              .setDefaultNestedTopicView(v),
        ),
        SwitchModel(
          id: 'openExternalLinksInAppBrowser',
          title: l10n.preferences_openLinksInApp,
          subtitle: l10n.preferences_openLinksInAppDesc,
          icon: Icons.open_in_browser_rounded,
          getValue: (ref) =>
              ref.watch(preferencesProvider).openExternalLinksInAppBrowser,
          onChanged: (ref, v) => ref
              .read(preferencesProvider.notifier)
              .setOpenExternalLinksInAppBrowser(v),
        ),
        PlatformConditionalModel(
          inner: ActionModel(
            id: 'externalBrowser',
            title: l10n.preferences_externalBrowser,
            subtitle: l10n.preferences_externalBrowserDesc,
            icon: Icons.public_rounded,
            getDynamicSubtitle: (ref) => _externalBrowserSubtitle(context, ref),
            onTap: (context, ref) => _showExternalBrowserPicker(context, ref),
          ),
          condition: () => Platform.isAndroid,
        ),
        SwitchModel(
          id: 'skipExternalLinkConfirmation',
          title: l10n.preferences_skipExternalLinkConfirmation,
          subtitle: l10n.preferences_skipExternalLinkConfirmationDesc,
          icon: Icons.open_in_new_rounded,
          getValue: (ref) =>
              ref.watch(preferencesProvider).skipExternalLinkConfirmation,
          onChanged: (ref, v) => ref
              .read(preferencesProvider.notifier)
              .setSkipExternalLinkConfirmation(v),
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
        SwitchModel(
          id: 'showSignatures',
          title: l10n.reading_showSignatures,
          subtitle: l10n.reading_showSignaturesDesc,
          icon: Icons.draw_rounded,
          getValue: (ref) => ref.watch(preferencesProvider).showSignatures,
          onChanged: (ref, v) =>
              ref.read(preferencesProvider.notifier).setShowSignatures(v),
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

String _externalBrowserSubtitle(BuildContext context, WidgetRef ref) {
  final selectedPackage = ref
      .watch(preferencesProvider)
      .externalBrowserPackageName;
  final browsersAsync = ref.watch(availableExternalBrowsersProvider);
  return browsersAsync.maybeWhen(
    data: (browsers) {
      if (selectedPackage == null || selectedPackage.isEmpty) {
        return context.l10n.preferences_externalBrowserSystemDefault;
      }
      for (final browser in browsers) {
        if (browser.packageName == selectedPackage) {
          return browser.label;
        }
      }
      return context.l10n.preferences_externalBrowserSystemDefault;
    },
    orElse: () => context.l10n.common_loading,
  );
}

String _pageTransitionLabel(
  BuildContext context,
  AppPageTransition transition,
) {
  final l10n = context.l10n;
  return switch (transition) {
    AppPageTransition.platform => l10n.pageTransition_platform,
    AppPageTransition.noSnapshot => l10n.pageTransition_noSnapshot,
    AppPageTransition.fade => l10n.pageTransition_fade,
    AppPageTransition.slide => l10n.pageTransition_slide,
    AppPageTransition.scale => l10n.pageTransition_scale,
    AppPageTransition.flip => l10n.pageTransition_flip,
    AppPageTransition.none => l10n.pageTransition_none,
  };
}

Future<void> _showPageTransitionPicker(
  BuildContext context,
  WidgetRef ref,
) async {
  final current = ref.read(preferencesProvider).pageTransition;
  final selected = await showAppDialog<AppPageTransition>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(context.l10n.preferences_pageTransition),
      children: [
        RadioGroup<AppPageTransition>(
          groupValue: current,
          onChanged: (value) => Navigator.of(dialogContext).pop(value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final transition in AppPageTransition.values)
                RadioListTile<AppPageTransition>(
                  title: Text(_pageTransitionLabel(context, transition)),
                  value: transition,
                ),
            ],
          ),
        ),
      ],
    ),
  );
  if (selected == null) return;
  await ref.read(preferencesProvider.notifier).setPageTransition(selected);
}

Future<void> _showExternalBrowserPicker(
  BuildContext context,
  WidgetRef ref,
) async {
  final currentPackage = ref
      .read(preferencesProvider)
      .externalBrowserPackageName;
  final browsers = await ref.read(availableExternalBrowsersProvider.future);
  if (!context.mounted) return;

  final selected = await showAppDialog<String>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(dialogContext.l10n.preferences_externalBrowser),
      children: [
        RadioGroup<String>(
          groupValue: currentPackage ?? _systemDefaultBrowserValue,
          onChanged: (value) => Navigator.of(dialogContext).pop(value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: Text(
                  dialogContext.l10n.preferences_externalBrowserSystemDefault,
                ),
                value: _systemDefaultBrowserValue,
              ),
              for (final browser in browsers)
                RadioListTile<String>(
                  title: Text(browser.label),
                  subtitle: Text(browser.packageName),
                  value: browser.packageName,
                ),
            ],
          ),
        ),
      ],
    ),
  );
  if (selected == null) return;
  await ref
      .read(preferencesProvider.notifier)
      .setExternalBrowserPackageName(
        selected == _systemDefaultBrowserValue ? null : selected,
      );
}
