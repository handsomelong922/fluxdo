import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_model_manager/ai_model_manager.dart';
import '../providers/app_icon_provider.dart';
import '../l10n/s.dart';
import '../providers/locale_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/theme_provider.dart';

class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final preferences = ref.watch(preferencesProvider);
    final locale = ref.watch(localeProvider);
    final theme = Theme.of(context);

    // Color swatches for selection
    final l10n = context.l10n;
    final List<ColorOption> colorOptions = [
      ColorOption(Colors.blue, l10n.appearance_colorBlue),
      ColorOption(Colors.purple, l10n.appearance_colorPurple),
      ColorOption(Colors.green, l10n.appearance_colorGreen),
      ColorOption(Colors.orange, l10n.appearance_colorOrange),
      ColorOption(Colors.pink, l10n.appearance_colorPink),
      ColorOption(Colors.teal, l10n.appearance_colorTeal),
      ColorOption(Colors.red, l10n.appearance_colorRed),
      ColorOption(Colors.indigo, l10n.appearance_colorIndigo),
      ColorOption(Colors.amber, l10n.appearance_colorAmber),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appearance_title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader(theme, l10n.appearance_language, Icons.language_outlined),
          const SizedBox(height: 16),
          _buildLanguageSelector(context, ref, locale),

          const SizedBox(height: 32),

          _buildSectionHeader(theme, l10n.appearance_themeMode, Icons.brightness_6_outlined),
          const SizedBox(height: 16),
          _buildModeSelector(context, ref, themeState.mode),

          const SizedBox(height: 32),

          _buildSectionHeader(theme, l10n.appearance_themeColor, Icons.color_lens_outlined),
          const SizedBox(height: 16),
          _buildColorGrid(context, ref, themeState.seedColor, colorOptions),

          // 应用图标（仅 iOS/Android）
          if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) ...[
            const SizedBox(height: 32),
            _buildSectionHeader(theme, l10n.appearance_appIcon, Icons.app_shortcut_outlined),
            const SizedBox(height: 16),
            _buildIconSelector(context, ref),
          ],

          const SizedBox(height: 32),

          _buildSectionHeader(theme, l10n.appearance_font, Icons.font_download_outlined),
          const SizedBox(height: 16),
          _buildFontSelector(context, ref, themeState),

          const SizedBox(height: 32),

          _buildSectionHeader(theme, l10n.appearance_reading, Icons.chrome_reader_mode_outlined),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.format_size_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.appearance_contentFontSize),
                            Text(
                              '${(preferences.contentFontScale * 100).round()}%',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: preferences.contentFontScale != 1.0
                            ? () => ref.read(preferencesProvider.notifier).setContentFontScale(1.0)
                            : null,
                        child: Text(l10n.common_reset),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    ),
                    child: Slider(
                      value: preferences.contentFontScale,
                      min: 0.8,
                      max: 1.4,
                      divisions: 12,
                      label: '${(preferences.contentFontScale * 100).round()}%',
                      onChanged: (value) {
                        ref.read(preferencesProvider.notifier).setContentFontScale(value);
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.appearance_small,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        l10n.appearance_large,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              title: Text(l10n.appearance_panguSpacing),
              subtitle: Text(l10n.appearance_panguSpacingDesc),
              secondary: Icon(
                Icons.auto_fix_high_rounded,
                color: preferences.displayPanguSpacing
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              value: preferences.displayPanguSpacing,
              onChanged: (value) {
                ref.read(preferencesProvider.notifier).setDisplayPanguSpacing(value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFontSelector(BuildContext context, WidgetRef ref, ThemeState themeState) {
    final l10n = context.l10n;
    final options = <(String, AppFontFamily)>[
      (l10n.appearance_fontSystem, AppFontFamily.system),
      ('MiSans', AppFontFamily.miSans),
    ];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: RadioGroup<AppFontFamily>(
        groupValue: themeState.fontFamily,
        onChanged: (value) {
          if (value != null) {
            ref.read(themeProvider.notifier).setFontFamily(value);
          }
        },
        child: Column(
          children: [
            for (final (label, fontFamily) in options)
              RadioListTile<AppFontFamily>(
                title: Text(
                  label,
                  style: fontFamily == AppFontFamily.miSans
                      ? const TextStyle(fontFamily: 'MiSans')
                      : null,
                ),
                value: fontFamily,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageSelector(BuildContext context, WidgetRef ref, Locale? currentLocale) {
    final l10n = context.l10n;
    final currentLabel = _localeLabel(l10n, currentLocale);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(Icons.translate, color: Theme.of(context).colorScheme.primary),
        title: Text(currentLabel),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showLanguagePicker(context, ref, currentLocale),
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, WidgetRef ref, Locale? currentLocale) {
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
                      ? Icon(Icons.check, color: Theme.of(sheetContext).colorScheme.primary)
                      : null,
                  onTap: () {
                    ref.read(localeProvider.notifier).setLocale(locale);
                    final effectiveLocale = locale ?? WidgetsBinding.instance.platformDispatcher.locale;
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

  static String _localeLabel(dynamic l10n, Locale? locale) {
    if (locale == null) return l10n.appearance_languageSystem;
    switch ('${locale.languageCode}_${locale.countryCode}') {
      case 'zh_CN': return l10n.appearance_languageZhCN;
      case 'zh_TW': return l10n.appearance_languageZhTW;
      case 'zh_HK': return l10n.appearance_languageZhHK;
      case 'en_US': return l10n.appearance_languageEn;
      default: return l10n.appearance_languageSystem;
    }
  }

  static String _localeKey(Locale? locale) {
    if (locale == null) return 'system';
    return locale.countryCode != null
        ? '${locale.languageCode}_${locale.countryCode}'
        : locale.languageCode;
  }

  Widget _buildIconSelector(BuildContext context, WidgetRef ref) {
    final iconState = ref.watch(appIconProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      children: [
        _buildIconOption(
          context, ref,
          style: AppIconStyle.classic,
          label: context.l10n.appearance_iconClassic,
          assetPath: isDark
              ? 'assets/images/icon_default_dark_preview.png'
              : 'assets/images/icon_default_preview.png',
          isSelected: iconState.currentStyle == AppIconStyle.classic,
          isChanging: iconState.isChanging,
          theme: theme,
        ),
        const SizedBox(width: 20),
        _buildIconOption(
          context, ref,
          style: AppIconStyle.modern,
          label: context.l10n.appearance_iconModern,
          assetPath: isDark
              ? 'assets/images/icon_modern_preview.png'
              : 'assets/images/icon_modern_light_preview.png',
          isSelected: iconState.currentStyle == AppIconStyle.modern,
          isChanging: iconState.isChanging,
          theme: theme,
        ),
      ],
    );
  }

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
              final success = await ref
                  .read(appIconProvider.notifier)
                  .setIconStyle(style);
              if (!success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.l10n.appearance_switchIconFailed)),
                );
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

  Widget _buildSectionHeader(ThemeData theme, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildModeSelector(BuildContext context, WidgetRef ref, ThemeMode currentMode) {
    return SegmentedButton<ThemeMode>(
      segments: [
        ButtonSegment(
          value: ThemeMode.system,
          label: Text(context.l10n.appearance_modeAuto),
          icon: const Icon(Icons.brightness_auto),
        ),
        ButtonSegment(
          value: ThemeMode.light,
          label: Text(context.l10n.appearance_modeLight),
          icon: const Icon(Icons.wb_sunny_outlined),
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          label: Text(context.l10n.appearance_modeDark),
          icon: const Icon(Icons.dark_mode_outlined),
        ),
      ],
      selected: {currentMode},
      onSelectionChanged: (Set<ThemeMode> newSelection) {
        ref.read(themeProvider.notifier).setThemeMode(newSelection.first);
      },
    );
  }

  Widget _buildColorGrid(
    BuildContext context, 
    WidgetRef ref, 
    Color currentColor, 
    List<ColorOption> options
  ) {
    final isDynamic = ref.watch(themeProvider.select((s) => s.useDynamicColor));
    
    final allItems = <Widget>[
      GestureDetector(
        onTap: () {
          ref.read(themeProvider.notifier).setUseDynamicColor(true);
        },
        child: _buildColorItem(
          context,
          color: Colors.transparent,
          isSelected: isDynamic,
          isDynamic: true,
        ),
      ),
      ...options.map((option) {
        final isSelected = !isDynamic && option.color.toARGB32() == currentColor.toARGB32();
        return GestureDetector(
          onTap: () {
            ref.read(themeProvider.notifier).setSeedColor(option.color);
          },
          child: _buildColorItem(
            context,
            color: option.color,
            isSelected: isSelected,
            isDynamic: false,
          ),
        );
      }),
    ];

    // 根据可用宽度计算每行个数，动态分配间距使左右对齐
    return LayoutBuilder(
      builder: (context, constraints) {
        const itemSize = 56.0;
        const minSpacing = 16.0;
        final crossAxisCount = ((constraints.maxWidth + minSpacing) / (itemSize + minSpacing)).floor();
        final spacing = (constraints.maxWidth - crossAxisCount * itemSize) / (crossAxisCount - 1);

        return Wrap(
          spacing: spacing,
          runSpacing: 16,
          children: allItems,
        );
      },
    );
  }

  Widget _buildColorItem(
    BuildContext context, {
    required Color color,
    required bool isSelected,
    required bool isDynamic,
  }) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected 
              ? Theme.of(context).colorScheme.primary 
              : Colors.transparent,
          width: 2,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: (isDynamic ? Theme.of(context).colorScheme.primary : color).withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 2,
                )
              ]
            : null,
      ),
      padding: const EdgeInsets.all(2), // Space for border
      child: isDynamic
          ? Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    Colors.blue,
                    Colors.purple,
                    Colors.green,
                    Colors.orange,
                    Colors.blue,
                  ],
                ),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
            )
          : ThemeColorPreview(seedColor: color),
    );
  }
}

class ThemeColorPreview extends StatelessWidget {
  final Color seedColor;

  const ThemeColorPreview({super.key, required this.seedColor});

  @override
  Widget build(BuildContext context) {
    // Generate a quick scheme for preview
    final scheme = ColorScheme.fromSeed(seedColor: seedColor);

    return ClipOval(
      child: CustomPaint(
        size: const Size(56, 56),
        painter: _PieChartPainter(scheme),
      ),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final ColorScheme scheme;

  _PieChartPainter(this.scheme);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final paint = Paint()..style = PaintingStyle.fill;

    // Left Half: Primary (180 degrees)
    paint.color = scheme.primary;
    canvas.drawArc(rect, 1.5 * 3.14159, 3.14159, true, paint); 
    // Start from top (270 or -90 deg)? No, 1.5 PI is 270 deg (Top). 
    // Arc is drawn clockwise. 
    // To match screenshot: Left half is Primary.
    // 90 deg (Bottom) to 270 deg (Top) is Left.
    // So start angle 90 deg (PI/2), sweep PI.
    
    // Correction:
    // 0 is Right. PI/2 is Bottom. PI is Left. 3PI/2 (or -PI/2) is Top.
    // Left Half = from Bottom (PI/2) to Top (3PI/2). Sweep = PI.
    canvas.drawArc(rect, 0.5 * 3.14159, 3.14159, true, paint);

    // Top Right Quarter: Secondary Container or Tertiary? Screenshot implies a lighter color.
    // Let's use PrimaryContainer or SurfaceVariant.
    paint.color = scheme.primaryContainer; 
    // From Top (3PI/2) to Right (0/2PI). Sweep = PI/2.
    canvas.drawArc(rect, 1.5 * 3.14159, 0.5 * 3.14159, true, paint);

    // Bottom Right Quarter: Tertiary or Secondary.
    paint.color = scheme.tertiary; 
    // From Right (0) to Bottom (PI/2). Sweep = PI/2.
    canvas.drawArc(rect, 0, 0.5 * 3.14159, true, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class ColorOption {
  final Color color;
  final String label;

  ColorOption(this.color, this.label);
}
