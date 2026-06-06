import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';

import 'ai_prompt_settings_page.dart';

/// 主应用包装的 AI 模型服务页。
///
/// `ai_model_manager` 是本地 package，不应反向依赖主应用页面；
/// 这里把 FluxDO 专属的“AI 提示词配置”作为二级设置注入进去。
class AiModelServicePage extends StatelessWidget {
  const AiModelServicePage({super.key, this.onOpenSession});

  final OpenSessionCallback? onOpenSession;

  @override
  Widget build(BuildContext context) {
    return AiProvidersPage(
      onOpenSession: onOpenSession,
      extraChatSettings: const [_AiPromptSettingsTile()],
    );
  }
}

class _AiPromptSettingsTile extends StatelessWidget {
  const _AiPromptSettingsTile();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AiPromptSettingsPage()));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.cyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.tune_rounded,
                color: Colors.cyan,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI 提示词配置', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    '配置总结、回复、标题生成和搜索助手 prompt',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: theme.colorScheme.outline.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
