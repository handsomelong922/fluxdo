import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_model_manager/ai_model_manager.dart';

import '../../l10n/s.dart';
import '../../providers/app_icon_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/toast_service.dart';
import '../settings_model.dart';

/// 外观设置数据声明
List<SettingsGroup> buildAppearanceGroups(BuildContext context) {
  final l10n = context.l10n;
  return [
    // ── 语言 ──────────────────────────────────────────────────────
    SettingsGroup(
      title: l10n.appearance_language,
      icon: Icons.language_outlined,
      items: [
        CustomModel(
          id: 'language',
          title: l10n.appearance_language,
          builder: (context, ref) {
            final locale = ref.watch(localeProvider);
            final label = _localeLabel(context.l10n, locale);
            return ListTile(
              leading: Icon(
                Icons.translate,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showLanguagePicker(context, ref, locale),
            );
          },
        ),
      ],
    ),

    // ── 主题模式 ───────────────────────────────────────────────────
    SettingsGroup(
      title: l10n.appearance_themeMode,
      icon: Icons.brightness_6_outlined,
      wrapInCard: false,
      items: [
        CustomModel(
          id: 'themeMode',
          title: l10n.appearance_themeMode,
          builder: (context, ref) {
            final themeState = ref.watch(themeProvider);
            final currentMode = themeState.mode;
            final seedColor = themeState.seedColor;
            final theme = Theme.of(context);
            final l10n = context.l10n;

            // 为每种模式生成预览配色
            final lightScheme = ColorScheme.fromSeed(
              seedColor: seedColor,
              brightness: Brightness.light,
            );
            final darkScheme = ColorScheme.fromSeed(
              seedColor: seedColor,
              brightness: Brightness.dark,
            );

            final modes = [
              (ThemeMode.system, Icons.auto_mode, l10n.appearance_modeAuto, null),
              (ThemeMode.light, Icons.light_mode, l10n.appearance_modeLight, lightScheme),
              (ThemeMode.dark, Icons.dark_mode, l10n.appearance_modeDark, darkScheme),
            ];

            return Row(
              children: [
                for (int i = 0; i < modes.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(
                    child: _ThemeModeCard(
                      mode: modes[i].$1,
                      icon: modes[i].$2,
                      label: modes[i].$3,
                      previewScheme: modes[i].$4,
                      lightScheme: lightScheme,
                      darkScheme: darkScheme,
                      isSelected: modes[i].$1 == currentMode,
                      currentTheme: theme,
                      onTap: () => ref
                          .read(themeProvider.notifier)
                          .setThemeMode(modes[i].$1),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    ),

    // ── 主题色 ────────────────────────────────────────────────────
    SettingsGroup(
      title: l10n.appearance_themeColor,
      icon: Icons.color_lens_outlined,
      wrapInCard: false,
      items: [
        CustomModel(
          id: 'themeColor',
          title: l10n.appearance_themeColor,
          builder: (context, ref) => const _ThemeColorSection(),
        ),
      ],
    ),

    // ── 应用图标（仅 iOS/Android）────────────────────────────────
    SettingsGroup(
      title: l10n.appearance_appIcon,
      icon: Icons.app_shortcut_outlined,
      wrapInCard: false,
      items: [
        PlatformConditionalModel(
          condition: () => !kIsWeb && (Platform.isIOS || Platform.isAndroid),
          inner: CustomModel(
            id: 'appIcon',
            title: l10n.appearance_appIcon,
            builder: (context, ref) {
              final iconState = ref.watch(appIconProvider);
              final theme = Theme.of(context);
              final isDark = theme.brightness == Brightness.dark;

              return Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _buildIconOption(
                      context,
                      ref,
                      style: AppIconStyle.classic,
                      label: context.l10n.appearance_iconClassic,
                      assetPath: isDark
                          ? 'assets/images/icon_default_dark_preview.png'
                          : 'assets/images/icon_default_preview.png',
                      isSelected:
                          iconState.currentStyle == AppIconStyle.classic,
                      isChanging: iconState.isChanging,
                      theme: theme,
                    ),
                    const SizedBox(width: 20),
                    _buildIconOption(
                      context,
                      ref,
                      style: AppIconStyle.modern,
                      label: context.l10n.appearance_iconModern,
                      assetPath: isDark
                          ? 'assets/images/icon_modern_preview.png'
                          : 'assets/images/icon_modern_light_preview.png',
                      isSelected:
                          iconState.currentStyle == AppIconStyle.modern,
                      isChanging: iconState.isChanging,
                      theme: theme,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ),

    // ── 字体 ──────────────────────────────────────────────────────
    SettingsGroup(
      title: l10n.appearance_font,
      icon: Icons.font_download_outlined,
      items: [
        CustomModel(
          id: 'font',
          title: l10n.appearance_font,
          builder: (context, ref) {
            final fontFamily =
                ref.watch(themeProvider.select((s) => s.fontFamily));
            final l10n = context.l10n;
            final options = <(String, AppFontFamily)>[
              (l10n.appearance_fontSystem, AppFontFamily.system),
              ('MiSans', AppFontFamily.miSans),
            ];

            return RadioGroup<AppFontFamily>(
              groupValue: fontFamily,
              onChanged: (value) {
                if (value != null) {
                  ref.read(themeProvider.notifier).setFontFamily(value);
                }
              },
              child: Column(
                children: [
                  for (final (label, ff) in options)
                    RadioListTile<AppFontFamily>(
                      title: Text(
                        label,
                        style: ff == AppFontFamily.miSans
                            ? const TextStyle(fontFamily: 'MiSans')
                            : null,
                      ),
                      value: ff,
                    ),
                ],
              ),
            );
          },
        ),
      ],
    ),
  ];
}

// ── 语言选择器辅助函数 ───────────────────────────────────────────

void _showLanguagePicker(
  BuildContext context,
  WidgetRef ref,
  Locale? currentLocale,
) {
  final l10n = context.l10n;
  final options = <(String, Locale?)>[
    (l10n.appearance_languageSystem, null),
    (l10n.appearance_languageZhCN, const Locale('zh', 'CN')),
    (l10n.appearance_languageZhTW, const Locale('zh', 'TW')),
    (l10n.appearance_languageZhHK, const Locale('zh', 'HK')),
    (l10n.appearance_languageEn, const Locale('en', 'US')),
  ];

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, locale) in options)
              ListTile(
                title: Text(label),
                trailing: _localeKey(locale) == _localeKey(currentLocale)
                    ? Icon(
                        Icons.check,
                        color: Theme.of(sheetContext).colorScheme.primary,
                      )
                    : null,
                onTap: () {
                  ref.read(localeProvider.notifier).setLocale(locale);
                  final effectiveLocale =
                      locale ??
                      WidgetsBinding.instance.platformDispatcher.locale;
                  AiL10n.configureLocale(effectiveLocale);
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      );
    },
  );
}

String _localeLabel(dynamic l10n, Locale? locale) {
  if (locale == null) return l10n.appearance_languageSystem;
  switch ('${locale.languageCode}_${locale.countryCode}') {
    case 'zh_CN':
      return l10n.appearance_languageZhCN;
    case 'zh_TW':
      return l10n.appearance_languageZhTW;
    case 'zh_HK':
      return l10n.appearance_languageZhHK;
    case 'en_US':
      return l10n.appearance_languageEn;
    default:
      return l10n.appearance_languageSystem;
  }
}

String _localeKey(Locale? locale) {
  if (locale == null) return 'system';
  return locale.countryCode != null
      ? '${locale.languageCode}_${locale.countryCode}'
      : locale.languageCode;
}

// ── 应用图标辅助函数 ──────────────────────────────────────────────

Widget _buildIconOption(
  BuildContext context,
  WidgetRef ref, {
  required AppIconStyle style,
  required String label,
  required String assetPath,
  required bool isSelected,
  required bool isChanging,
  required ThemeData theme,
}) {
  return GestureDetector(
    onTap: isChanging
        ? null
        : () async {
            final l10n = context.l10n;
            final success =
                await ref.read(appIconProvider.notifier).setIconStyle(style);
            if (!success) {
              ToastService.showError(l10n.appearance_switchIconFailed);
            }
          },
    child: Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : Colors.transparent,
              width: 2.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                Image.asset(
                  assetPath,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                ),
                if (isChanging && isSelected)
                  Container(
                    width: 72,
                    height: 72,
                    color: Colors.black26,
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    ),
  );
}

/// 主题模式选择卡片
///
/// 顶部绘制一个迷你 "屏幕" 模拟该模式下的配色，
/// 底部显示图标和文字，选中态高亮边框 + 勾选角标。
class _ThemeModeCard extends StatelessWidget {
  final ThemeMode mode;
  final IconData icon;
  final String label;

  /// 该模式对应的配色方案，system 模式为 null（需同时展示 light + dark）
  final ColorScheme? previewScheme;
  final ColorScheme lightScheme;
  final ColorScheme darkScheme;
  final bool isSelected;
  final ThemeData currentTheme;
  final VoidCallback onTap;

  const _ThemeModeCard({
    required this.mode,
    required this.icon,
    required this.label,
    required this.previewScheme,
    required this.lightScheme,
    required this.darkScheme,
    required this.isSelected,
    required this.currentTheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = currentTheme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: isSelected
              ? cs.secondaryContainer.withValues(alpha: 0.5)
              : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? cs.primary
                : cs.outlineVariant.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            // 迷你屏幕预览
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: _buildPreview(),
            ),
            const SizedBox(height: 8),
            // 图标 + 文字
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: currentTheme.textTheme.labelSmall?.copyWith(
                      color: isSelected ? cs.primary : cs.onSurfaceVariant,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 绘制迷你屏幕预览
  Widget _buildPreview() {
    if (mode == ThemeMode.system) {
      // 跟随系统：同一个屏幕，左半亮色右半暗色
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 64,
          child: CustomPaint(
            painter: _SplitThemePreviewPainter(
              lightScheme: lightScheme,
              darkScheme: darkScheme,
            ),
            size: Size.infinite,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 64,
        child: _buildMiniScreen(previewScheme!),
      ),
    );
  }

  /// 单个迷你屏幕：模拟 app bar + 内容行
  Widget _buildMiniScreen(ColorScheme scheme) {
    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 模拟 app bar
          Container(
            height: 10,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(
              children: [
                const SizedBox(width: 3),
                Container(
                  width: 16,
                  height: 5,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          // 模拟内容行
          _buildContentLine(scheme, 0.7),
          const SizedBox(height: 2),
          _buildContentLine(scheme, 0.5),
          const SizedBox(height: 2),
          // 模拟按钮
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 14,
              height: 6,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildContentLine(ColorScheme scheme, double widthFactor) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: 4,
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// 跟随系统预览：同一个屏幕背景，左半亮色右半暗色，
/// UI 元素在分界线处自然切换颜色。
class _SplitThemePreviewPainter extends CustomPainter {
  final ColorScheme lightScheme;
  final ColorScheme darkScheme;

  _SplitThemePreviewPainter({
    required this.lightScheme,
    required this.darkScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final midX = size.width / 2;
    final paint = Paint();

    // ── 背景：左亮右暗 ──
    paint.color = lightScheme.surface;
    canvas.drawRect(Rect.fromLTRB(0, 0, midX, size.height), paint);
    paint.color = darkScheme.surface;
    canvas.drawRect(Rect.fromLTRB(midX, 0, size.width, size.height), paint);

    final pad = 4.0;

    // ── app bar 背景条 ──
    _drawSplitRRect(
      canvas, size,
      rect: Rect.fromLTWH(pad, pad, size.width - pad * 2, 10),
      radius: 3,
      lightColor: lightScheme.surfaceContainerHighest,
      darkColor: darkScheme.surfaceContainerHighest,
    );

    // ── app bar 标题 ──
    _drawSplitRRect(
      canvas, size,
      rect: Rect.fromLTWH(pad + 3, pad + 2.5, 16, 5),
      radius: 2,
      lightColor: lightScheme.onSurface.withValues(alpha: 0.6),
      darkColor: darkScheme.onSurface.withValues(alpha: 0.6),
    );

    // ── 内容行 1 ──
    final y1 = pad + 13.0;
    _drawSplitRRect(
      canvas, size,
      rect: Rect.fromLTWH(pad, y1, (size.width - pad * 2) * 0.7, 4),
      radius: 2,
      lightColor: lightScheme.onSurface.withValues(alpha: 0.15),
      darkColor: darkScheme.onSurface.withValues(alpha: 0.15),
    );

    // ── 内容行 2 ──
    final y2 = y1 + 6;
    _drawSplitRRect(
      canvas, size,
      rect: Rect.fromLTWH(pad, y2, (size.width - pad * 2) * 0.5, 4),
      radius: 2,
      lightColor: lightScheme.onSurface.withValues(alpha: 0.15),
      darkColor: darkScheme.onSurface.withValues(alpha: 0.15),
    );

    // ── 按钮 ──
    final btnW = 14.0;
    final btnH = 6.0;
    final btnY = y2 + 8;
    _drawSplitRRect(
      canvas, size,
      rect: Rect.fromLTWH(size.width - pad - btnW, btnY, btnW, btnH),
      radius: 3,
      lightColor: lightScheme.primary,
      darkColor: darkScheme.primary,
    );

    // ── 中线分隔（半透明细线，暗示分界）──
    paint
      ..color = lightScheme.outline.withValues(alpha: 0.1)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(midX, 0), Offset(midX, size.height), paint);
  }

  /// 绘制一个跨越亮暗分界的圆角矩形，
  /// 左半用 lightColor，右半用 darkColor。
  void _drawSplitRRect(
    Canvas canvas,
    Size size, {
    required Rect rect,
    required double radius,
    required Color lightColor,
    required Color darkColor,
  }) {
    final midX = size.width / 2;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final paint = Paint();

    // 左半（亮色）
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, midX, size.height));
    paint.color = lightColor;
    canvas.drawRRect(rrect, paint);
    canvas.restore();

    // 右半（暗色）
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(midX, 0, size.width, size.height));
    paint.color = darkColor;
    canvas.drawRRect(rrect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SplitThemePreviewPainter oldDelegate) {
    return oldDelegate.lightScheme != lightScheme ||
        oldDelegate.darkScheme != darkScheme;
  }
}

// ══════════════════════════════════════════════════════════════════
// 主题色选择器（含方案变体 + 自定义色 + 长按删除）
// ══════════════════════════════════════════════════════════════════

class _ThemeColorSection extends ConsumerStatefulWidget {
  const _ThemeColorSection();

  @override
  ConsumerState<_ThemeColorSection> createState() => _ThemeColorSectionState();
}

class _ThemeColorSectionState extends ConsumerState<_ThemeColorSection> {
  Color? _removableColor;

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDynamic = themeState.useDynamicColor;
    final currentColor = themeState.seedColor;
    final variant = themeState.schemeVariant;
    final customColors = themeState.customColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 方案变体 chip
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final v in DynamicSchemeVariant.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(_variantLabel(context, v)),
                    selected: v == variant,
                    onSelected: (_) =>
                        ref.read(themeProvider.notifier).setSchemeVariant(v),
                    visualDensity: VisualDensity.compact,
                    labelStyle: theme.textTheme.labelSmall,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 颜色网格
        LayoutBuilder(
          builder: (context, constraints) {
            const itemSize = 64.0;
            const spacing = 12.0;
            final columns =
                ((constraints.maxWidth + spacing) / (itemSize + spacing))
                    .floor()
                    .clamp(3, 10);
            final actualSpacing =
                (constraints.maxWidth - columns * itemSize) / (columns - 1);

            return Wrap(
              spacing: actualSpacing,
              runSpacing: actualSpacing,
              children: [
                // 动态色
                _ColorTile(
                  size: itemSize,
                  isSelected: isDynamic,
                  isDynamic: true,
                  variant: variant,
                  onTap: () {
                    setState(() => _removableColor = null);
                    ref.read(themeProvider.notifier).setUseDynamicColor(true);
                  },
                ),
                // 预设色
                for (final color in ThemeNotifier.presetColors)
                  _ColorTile(
                    size: itemSize,
                    seedColor: color,
                    isSelected: !isDynamic &&
                        color.toARGB32() == currentColor.toARGB32(),
                    variant: variant,
                    onTap: () {
                      setState(() => _removableColor = null);
                      ref.read(themeProvider.notifier).setSeedColor(color);
                    },
                  ),
                // 自定义色
                for (final color in customColors)
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _ColorTile(
                        size: itemSize,
                        seedColor: color,
                        isSelected: !isDynamic &&
                            color.toARGB32() == currentColor.toARGB32(),
                        variant: variant,
                        onTap: () {
                          setState(() => _removableColor = null);
                          ref.read(themeProvider.notifier).setSeedColor(color);
                        },
                        onLongPress: () =>
                            setState(() => _removableColor = color),
                      ),
                      if (_removableColor?.toARGB32() == color.toARGB32())
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: () async {
                              ref
                                  .read(themeProvider.notifier)
                                  .removeCustomColor(color);
                              setState(() => _removableColor = null);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.delete_rounded,
                                  color: Colors.white, size: 22),
                            ),
                          ),
                        ),
                    ],
                  ),
                // 添加按钮
                if (_removableColor == null)
                  SizedBox(
                    width: itemSize,
                    height: itemSize,
                    child: Material(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _showColorPicker(context),
                        child: Icon(Icons.add_rounded,
                            color: cs.onSurfaceVariant, size: 24),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _showColorPicker(BuildContext context) {
    double hue = 0;
    double saturation = 0.8;
    double value = 0.9;

    showModalBottomSheet<Color>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final color =
                HSVColor.fromAHSV(1.0, hue, saturation, value).toColor();
            final scheme = ColorScheme.fromSeed(seedColor: color);

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 预览
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _SchemePreviewTile(scheme: scheme, size: 48),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'H:${hue.round()} S:${(saturation * 100).round()}% V:${(value * 100).round()}%',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 色相
                    _buildSliderRow(
                      context, 'H', hue, 0, 360,
                      activeColor: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                      onChanged: (v) => setSheetState(() => hue = v),
                    ),
                    const SizedBox(height: 8),
                    // 饱和度
                    _buildSliderRow(
                      context, 'S', saturation, 0, 1,
                      activeColor: HSVColor.fromAHSV(1, hue, saturation, 1).toColor(),
                      onChanged: (v) => setSheetState(() => saturation = v),
                    ),
                    const SizedBox(height: 8),
                    // 明度
                    _buildSliderRow(
                      context, 'V', value, 0, 1,
                      activeColor: HSVColor.fromAHSV(1, hue, 0, value).toColor(),
                      onChanged: (v) => setSheetState(() => value = v),
                    ),
                    const SizedBox(height: 20),

                    // 确认按钮
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetContext, color),
                        child: Text(context.l10n.common_confirm),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((color) {
      if (color != null) {
        ref.read(themeProvider.notifier).addCustomColor(color);
        ref.read(themeProvider.notifier).setSeedColor(color);
      }
    });
  }

  Widget _buildSliderRow(
    BuildContext context,
    String label,
    double value,
    double min,
    double max, {
    required Color activeColor,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          child: Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              activeTrackColor: activeColor,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  String _variantLabel(BuildContext context, DynamicSchemeVariant v) {
    final l10n = context.l10n;
    return switch (v) {
      DynamicSchemeVariant.tonalSpot => l10n.schemeVariant_tonalSpot,
      DynamicSchemeVariant.fidelity => l10n.schemeVariant_fidelity,
      DynamicSchemeVariant.monochrome => l10n.schemeVariant_monochrome,
      DynamicSchemeVariant.neutral => l10n.schemeVariant_neutral,
      DynamicSchemeVariant.vibrant => l10n.schemeVariant_vibrant,
      DynamicSchemeVariant.expressive => l10n.schemeVariant_expressive,
      DynamicSchemeVariant.content => l10n.schemeVariant_content,
      DynamicSchemeVariant.rainbow => l10n.schemeVariant_rainbow,
      DynamicSchemeVariant.fruitSalad => l10n.schemeVariant_fruitSalad,
    };
  }
}

/// 单个颜色方格：三色预览（primary/secondary/tertiary）
class _ColorTile extends StatelessWidget {
  final double size;
  final Color? seedColor;
  final bool isSelected;
  final bool isDynamic;
  final DynamicSchemeVariant variant;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ColorTile({
    required this.size,
    this.seedColor,
    required this.isSelected,
    this.isDynamic = false,
    required this.variant,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: 0.3),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isSelected ? 12 : 13),
          child: isDynamic ? _buildDynamicPreview() : _buildSchemePreview(),
        ),
      ),
    );
  }

  Widget _buildDynamicPreview() {
    return Container(
      decoration: const BoxDecoration(
        gradient: SweepGradient(
          colors: [
            Colors.blue,
            Colors.purple,
            Colors.pink,
            Colors.orange,
            Colors.amber,
            Colors.green,
            Colors.teal,
            Colors.blue,
          ],
        ),
      ),
      child: const Center(
        child: Icon(Icons.auto_awesome, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildSchemePreview() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor!,
      dynamicSchemeVariant: variant,
    );

    return Container(
      color: scheme.primary,
      child: Stack(
        children: [
          // 底部两个圆角药丸：secondary + tertiary
          Positioned(
            left: 5,
            right: 5,
            bottom: 5,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: scheme.secondary,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: scheme.tertiary,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 右上角 primaryContainer 小圆点
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 调色板预览方格（与 _ColorTile 风格一致）
class _SchemePreviewTile extends StatelessWidget {
  final ColorScheme scheme;
  final double size;

  const _SchemePreviewTile({required this.scheme, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 4,
            right: 4,
            bottom: 4,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: scheme.secondary,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: scheme.tertiary,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 5,
            right: 5,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
