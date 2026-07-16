import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/core_providers.dart';
import '../../../services/network/cookie/login_cookie_diagnostics_service.dart';
import '../../../utils/time_utils.dart';

final _loginCookieDiagnosticsProvider =
    FutureProvider.autoDispose<LoginCookieDiagnostics>((ref) async {
      final isLoggedIn = ref.watch(
        currentUserProvider.select((value) => value.value != null),
      );
      return ref
          .watch(loginCookieDiagnosticsServiceProvider)
          .load(isLoggedIn: isLoggedIn);
    });

class LoginCookieDiagnosticsCard extends ConsumerWidget {
  const LoginCookieDiagnosticsCard({super.key});

  static const double stableMinHeight = 132;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final diagnostics = ref.watch(_loginCookieDiagnosticsProvider);

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: stableMinHeight),
        child: diagnostics.when(
          data: (data) => _buildContent(context, ref, theme, data),
          loading: () => const ListTile(
            leading: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('登录状态诊断'),
            subtitle: Text('正在检查本地登录 Cookie 状态'),
          ),
          error: (error, _) => ListTile(
            leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
            title: const Text('登录状态诊断'),
            subtitle: Text('读取诊断失败：$error'),
            trailing: IconButton(
              tooltip: '重新检查',
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(_loginCookieDiagnosticsProvider),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    LoginCookieDiagnostics data,
  ) {
    final color = data.looksHealthy
        ? theme.colorScheme.primary
        : data.hasDuplicateRisk
        ? theme.colorScheme.error
        : theme.colorScheme.tertiary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(_iconFor(data), color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('登录状态诊断', style: theme.textTheme.titleMedium),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        data.statusLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _formatDetails(data),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '仅显示布尔状态和数量，不显示 Cookie 原文 · ${TimeUtils.formatCompactTime(data.checkedAt)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.75,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '重新检查',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_loginCookieDiagnosticsProvider),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(LoginCookieDiagnostics data) {
    if (data.looksHealthy) return Icons.verified_user_outlined;
    if (data.hasDuplicateRisk) return Icons.warning_amber_outlined;
    return Icons.manage_search_outlined;
  }

  String _formatDetails(LoginCookieDiagnostics data) {
    final duplicateText = data.hasDuplicateRisk
        ? data.duplicateSessionCookieNames.join(', ')
        : '无';
    return [
      'App 登录：${data.isLoggedIn ? '是' : '否'}',
      '_t：${data.hasTToken ? '存在' : '缺失'}',
      '_forum_session：${data.hasForumSession ? '存在' : '缺失'}',
      'cf_clearance：${data.hasCfClearance ? '存在' : '缺失'}',
      '会话 Cookie 数：${data.sessionCookieCount}',
      '多副本风险：$duplicateText',
    ].join(' · ');
  }
}
