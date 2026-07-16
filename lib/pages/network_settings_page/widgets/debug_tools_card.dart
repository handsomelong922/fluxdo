import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../l10n/s.dart';
import '../../../utils/share_utils.dart';
import '../../../services/network_logger.dart';
import '../../../services/log/app_log_settings_service.dart';
import '../../../services/performance_diagnostics_service.dart';
import '../../../utils/dialog_utils.dart';
import '../../../services/cf_challenge_service.dart';
import '../../../services/cf_challenge_logger.dart';
import '../../../services/toast_service.dart';
import '../../../widgets/log/app_log_settings_sheet.dart';
import '../../../providers/theme_provider.dart';

/// 调试工具卡片
class DebugToolsCard extends ConsumerStatefulWidget {
  const DebugToolsCard({super.key});

  @override
  ConsumerState<DebugToolsCard> createState() => _DebugToolsCardState();
}

class _DebugToolsCardState extends ConsumerState<DebugToolsCard> {
  late final bool _isDeveloperMode;

  @override
  void initState() {
    super.initState();
    // SharedPreferences 已在应用启动时完成初始化，首帧直接读取，避免用户滚动
    // 网络设置时调试区异步插入多行控件并改变 maxScrollExtent。
    _isDeveloperMode =
        ref.read(sharedPreferencesProvider).getBool('developer_mode') ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cfStatus = CfChallengeService().status;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: AppLogSettingsService.instance,
            builder: (context, _) {
              final settings = AppLogSettingsService.instance.settings;
              return ListTile(
                leading: Icon(
                  settings.enabled
                      ? Icons.receipt_long_outlined
                      : Icons.receipt_long_rounded,
                ),
                title: const Text('日志记录设置'),
                subtitle: Text(
                  AppLogSettingsService.describeSettings(settings),
                ),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => showAppLogSettingsSheet(context),
              );
            },
          ),
          Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
          AnimatedBuilder(
            animation: PerformanceDiagnosticsService.instance,
            builder: (context, _) {
              final diagnostics = PerformanceDiagnosticsService.instance;
              return Column(
                children: [
                  ListTile(
                    leading: Icon(
                      diagnostics.enabled
                          ? Icons.monitor_heart_outlined
                          : Icons.speed_outlined,
                    ),
                    title: const Text('性能诊断模式'),
                    subtitle: Text(diagnostics.statusDescription),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => showAppLogSettingsSheet(context),
                  ),
                  if (diagnostics.enabled) ...[
                    Divider(
                      height: 1,
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.2,
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.add_location_alt_outlined),
                      title: const Text('标记当前卡顿'),
                      subtitle: const Text('感觉开始掉帧时点一下，日志会保存当前现场'),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: _markPerformanceJank,
                    ),
                  ],
                  Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.2,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.ios_share_outlined),
                    title: const Text('导出性能诊断日志'),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: _sharePerformanceTrace,
                  ),
                  Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.2,
                    ),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      '清除性能诊断日志',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: theme.colorScheme.error,
                    ),
                    onTap: _clearPerformanceTrace,
                  ),
                ],
              );
            },
          ),
          Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: Text(context.l10n.appLogs_title),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: _showLogSheet,
          ),
          Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: Text(context.l10n.appLogs_shareLogs),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: _shareLogs,
          ),
          Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_sweep_outlined,
              color: theme.colorScheme.error,
            ),
            title: Text(
              context.l10n.appLogs_clearLogs,
              style: TextStyle(color: theme.colorScheme.error),
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: 20,
              color: theme.colorScheme.error,
            ),
            onTap: _clearLogs,
          ),
          // CF 验证日志（开发者模式）
          if (_isDeveloperMode) ...[
            Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            ),
            ListTile(
              leading: Icon(
                cfStatus.isInCooldown
                    ? Icons.pause_circle_outline
                    : cfStatus.isVerifying
                    ? Icons.verified_user_outlined
                    : Icons.shield_outlined,
              ),
              title: const Text('CF 验证状态'),
              subtitle: Text(_formatCfStatus(cfStatus)),
            ),
            Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            ),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('CF 验证日志'),
              subtitle: const Text('查看 Cloudflare 验证详情'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: _showCfChallengeLogSheet,
            ),
            Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('导出 CF 日志'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: _shareCfChallengeLogs,
            ),
            Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
              ),
              title: Text(
                '清除 CF 日志',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              trailing: Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.error,
              ),
              onTap: _clearCfChallengeLogs,
            ),
          ],
        ],
      ),
    );
  }

  String _formatCfStatus(CfChallengeStatus status) {
    final parts = <String>[
      status.isVerifying ? '验证中' : '空闲',
      '失败 ${status.consecutiveFailures} 次',
    ];
    if (status.cooldownRemaining != null) {
      parts.add('冷却剩余 ${status.cooldownRemaining!.inSeconds}s');
    }
    if (status.silentVerifyDeferredRemaining != null) {
      parts.add('后台验证延后 ${status.silentVerifyDeferredRemaining!.inSeconds}s');
    }
    if (status.lastToastAt != null) {
      parts.add('通知间隔 ${status.toastCooldown.inSeconds}s');
    }
    return parts.join(' · ');
  }

  Future<void> _showLogSheet() async {
    final logs = await NetworkLogger.readLogs();
    if (!mounted) return;

    final theme = Theme.of(context);
    await showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // 拖动条
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // 标题栏
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        '调试日志',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: context.l10n.common_copy,
                        onPressed: logs == null || logs.isEmpty
                            ? null
                            : () {
                                Clipboard.setData(ClipboardData(text: logs));
                                ToastService.showSuccess(
                                  S.current.common_copiedToClipboard,
                                );
                              },
                      ),
                      IconButton(
                        icon: const Icon(Icons.share),
                        tooltip: context.l10n.common_share,
                        onPressed: logs == null || logs.isEmpty
                            ? null
                            : () {
                                Navigator.pop(context);
                                _shareLogs();
                              },
                      ),
                    ],
                  ),
                ),
                const Divider(),
                // 日志内容
                Expanded(
                  child: logs == null || logs.isEmpty
                      ? _buildEmptyLog(theme)
                      : SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
                            logs,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: 1.5,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyLog(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.article_outlined,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.appLogs_noLogs,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '启用 DOH 并发起请求后会产生日志',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareLogs() async {
    final logs = await NetworkLogger.readLogs();
    if (logs == null || logs.isEmpty) {
      if (!mounted) return;
      ToastService.showInfo('暂无日志可分享');
      return;
    }

    final path = await NetworkLogger.getLogPath();
    if (path != null) {
      await ShareUtils.shareOrSaveFile(XFile(path), subject: 'DOH 调试日志');
    } else {
      await SharePlus.instance.share(
        ShareParams(text: logs, subject: 'DOH 调试日志'),
      );
    }
  }

  Future<void> _clearLogs() async {
    final confirm = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.appLogs_clearTitle),
        content: Text(context.l10n.appLogs_clearContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.l10n.common_clear),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await NetworkLogger.clear();
      if (mounted) {
        ToastService.showSuccess(S.current.appLogs_logsCleared);
      }
    }
  }

  Future<void> _markPerformanceJank() async {
    if (!PerformanceDiagnosticsService.instance.enabled) {
      ToastService.showInfo('性能诊断模式未开启');
      return;
    }
    PerformanceDiagnosticsService.instance.markCurrentJank(
      source: 'debug_card',
    );
    ToastService.showSuccess('已标记当前卡顿现场');
  }

  Future<void> _sharePerformanceTrace() async {
    final logs = await PerformanceDiagnosticsService.instance.readLogs();
    if (logs == null || logs.trim().isEmpty) {
      if (!mounted) return;
      ToastService.showInfo('暂无性能诊断日志可分享');
      return;
    }

    final path = await PerformanceDiagnosticsService.instance.getLogPath();
    if (!mounted) return;
    if (path != null) {
      await ShareUtils.shareOrSaveFile(XFile(path), subject: '性能诊断日志');
    } else {
      await SharePlus.instance.share(
        ShareParams(text: logs, subject: '性能诊断日志'),
      );
    }
  }

  Future<void> _clearPerformanceTrace() async {
    final confirm = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.appLogs_clearTitle),
        content: const Text('确定要清除性能诊断日志吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.l10n.common_clear),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await PerformanceDiagnosticsService.instance.clear();
      if (mounted) {
        ToastService.showSuccess(S.current.appLogs_logsCleared);
      }
    }
  }

  Future<void> _showCfChallengeLogSheet() async {
    final logs = await CfChallengeLogger.readLogs();
    if (!mounted) return;

    final theme = Theme.of(context);
    await showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // 拖动条
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // 标题栏
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        'CF 验证日志',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: context.l10n.common_copy,
                        onPressed: logs == null || logs.isEmpty
                            ? null
                            : () {
                                Clipboard.setData(ClipboardData(text: logs));
                                ToastService.showSuccess(
                                  S.current.common_copiedToClipboard,
                                );
                              },
                      ),
                      IconButton(
                        icon: const Icon(Icons.share),
                        tooltip: context.l10n.common_share,
                        onPressed: logs == null || logs.isEmpty
                            ? null
                            : () {
                                Navigator.pop(context);
                                _shareCfChallengeLogs();
                              },
                      ),
                    ],
                  ),
                ),
                const Divider(),
                // 日志内容
                Expanded(
                  child: logs == null || logs.isEmpty
                      ? _buildEmptyCfLog(theme)
                      : SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
                            logs,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: 1.5,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyCfLog(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bug_report_outlined,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无 CF 验证日志',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '触发 CF 验证后会产生日志',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareCfChallengeLogs() async {
    final logs = await CfChallengeLogger.readLogs();
    if (logs == null || logs.isEmpty) {
      if (!mounted) return;
      ToastService.showInfo('暂无 CF 日志可分享');
      return;
    }

    final path = await CfChallengeLogger.getLogPath();
    if (path != null) {
      await ShareUtils.shareOrSaveFile(XFile(path), subject: 'CF 验证日志');
    } else {
      await SharePlus.instance.share(
        ShareParams(text: logs, subject: 'CF 验证日志'),
      );
    }
  }

  Future<void> _clearCfChallengeLogs() async {
    final confirm = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.appLogs_clearTitle),
        content: Text(context.l10n.appLogs_clearContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.l10n.common_clear),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await CfChallengeLogger.clear();
      if (mounted) {
        ToastService.showSuccess(S.current.appLogs_logsCleared);
      }
    }
  }
}
