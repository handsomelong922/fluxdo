import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import '../../providers/personal_navigation_preferences_provider.dart';
import '../settings_model.dart';

List<SettingsModel> buildPersonalNavigationSettings(BuildContext context) {
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  String label(PageTransitionStyle style) => switch (style) {
    PageTransitionStyle.cupertino => zh ? '滑动（默认）' : 'Slide (default)',
    PageTransitionStyle.fade => zh ? '淡入淡出' : 'Fade',
    PageTransitionStyle.scale => zh ? '缩放' : 'Scale',
    PageTransitionStyle.none => zh ? '无动画' : 'None',
  };
  return [
    SwitchModel(
      id: 'rightEdgeTapPreview',
      title: zh ? '点击卡片右侧预览' : 'Tap card’s right edge to preview',
      subtitle: zh ? '点击右侧 25% 区域预览，可与长按同时开启' : 'Tap the rightmost 25%; works alongside long press',
      icon: Symbols.touch_app_rounded,
      getValue: (ref) => ref.watch(personalNavigationPreferencesProvider).rightEdgeTapPreview,
      onChanged: (ref, value) => ref.read(personalNavigationPreferencesProvider.notifier).setRightEdgeTapPreview(value),
    ),
    ActionModel(
      id: 'pageTransitionStyle',
      title: zh ? '页面过渡动画' : 'Page transition',
      icon: Symbols.swap_horiz_rounded,
      getDynamicSubtitle: (ref) => label(ref.watch(personalNavigationPreferencesProvider).pageTransitionStyle),
      onTap: (context, ref) async {
        final selected = await showDialog<PageTransitionStyle>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(zh ? '页面过渡动画' : 'Page transition'),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(zh ? '用于普通页面打开和返回（含手势）；媒体查看器保留专属转场。淡入淡出可能增加渲染开销。' : 'Applies to standard page navigation and back gestures. Media viewers keep their own transitions. Fade may increase rendering cost.'),
              ),
              for (final style in PageTransitionStyle.values)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, style),
                  child: Text(label(style)),
                ),
            ],
          ),
        );
        if (selected != null && context.mounted) {
          await ref.read(personalNavigationPreferencesProvider.notifier).setPageTransitionStyle(selected);
        }
      },
    ),
  ];
}
