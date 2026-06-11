import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/s.dart';
import '../../../providers/preferences_provider.dart';

/// 限流设置卡片
class RateLimitCard extends ConsumerWidget {
  const RateLimitCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider);
    final notifier = ref.read(preferencesProvider.notifier);

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            _SliderTile(
              icon: Icons.swap_horiz,
              label: context.l10n.networkSettings_maxConcurrent,
              value: prefs.maxConcurrent,
              min: 1,
              max: 10,
              onChanged: (v) => notifier.setMaxConcurrent(v),
            ),
            const Divider(height: 1, indent: 56),
            _SliderTile(
              icon: Icons.speed,
              label: context.l10n.networkSettings_maxPerWindow,
              value: prefs.maxPerWindow,
              min: 2,
              max: 30,
              onChanged: (v) => notifier.setMaxPerWindow(v),
            ),
            const Divider(height: 1, indent: 56),
            _SliderTile(
              icon: Icons.timer_outlined,
              label: context.l10n.networkSettings_windowSeconds,
              value: prefs.windowSeconds,
              min: 1,
              max: 10,
              suffix: context.l10n.networkSettings_windowSecondsSuffix,
              onChanged: (v) => notifier.setWindowSeconds(v),
            ),
            const Divider(height: 1, indent: 56),
            _SliderTile(
              icon: Icons.hourglass_bottom_rounded,
              label: '请求最小间隔',
              value: prefs.minRequestIntervalMs,
              min: 0,
              max: 1000,
              suffix: 'ms',
              onChanged: (v) => notifier.setMinRequestIntervalMs(v),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
              child: Text(
                '并发数控制同时请求数量，窗口上限控制一段时间内的请求总量；最小间隔用于削平瞬时突发，调高后更不容易触发 429，但列表加载会更稳更慢。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final int min;
  final int max;
  final String? suffix;
  final ValueChanged<int> onChanged;

  const _SliderTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 22, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                  ),
                  child: Slider(
                    value: value.toDouble(),
                    min: min.toDouble(),
                    max: max.toDouble(),
                    divisions: max - min,
                    label: suffix != null ? '$value $suffix' : '$value',
                    onChanged: (v) => onChanged(v.round()),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              suffix != null ? '$value$suffix' : '$value',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.primary,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
