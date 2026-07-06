import 'package:flutter/material.dart';

import '../../services/log/app_log_settings_service.dart';
import '../../services/performance_diagnostics_service.dart';
import '../../utils/dialog_utils.dart';

Future<void> showAppLogSettingsSheet(BuildContext context) {
  return showAppBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => const _AppLogSettingsSheet(),
  );
}

class _AppLogSettingsSheet extends StatelessWidget {
  const _AppLogSettingsSheet();

  @override
  Widget build(BuildContext context) {
    final service = AppLogSettingsService.instance;
    final diagnosticsService = PerformanceDiagnosticsService.instance;
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([service, diagnosticsService]),
      builder: (context, _) {
        final settings = service.settings;
        final diagnosticsEnabled = diagnosticsService.enabled;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '日志记录设置',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '关闭后，应用日志、启动请求耗时榜，以及高频调试日志都会停止记录。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('记录应用日志'),
                  subtitle: Text(
                    AppLogSettingsService.describeSettings(settings),
                  ),
                  value: settings.enabled,
                  onChanged: (value) => service.setEnabled(value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('性能诊断模式'),
                  subtitle: Text(diagnosticsService.statusDescription),
                  value: diagnosticsEnabled,
                  onChanged: (value) => diagnosticsService.setEnabled(value),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '开启后会独立记录慢帧、滚动、路由、触摸和资源快照，用于定位“越用越卡”的触发链路。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '日志保留上限',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '范围 50~300 条，按 25 条递增；达到上限后会自动丢弃最早的记录。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 20,
                      color: settings.enabled
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Slider(
                        value: settings.maxEntries.toDouble(),
                        min: AppLogSettingsService.minEntries.toDouble(),
                        max: AppLogSettingsService.maxEntries.toDouble(),
                        divisions:
                            (AppLogSettingsService.maxEntries -
                                AppLogSettingsService.minEntries) ~/
                            AppLogSettingsService.stepEntries,
                        label: '${settings.maxEntries} 条',
                        onChanged: (value) => service.setMaxEntries(
                          AppLogSettingsService.normalizeMaxEntries(
                            value.round(),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        '${settings.maxEntries} 条',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: settings.enabled
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
