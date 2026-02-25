import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_provider.dart';
import '../providers/ai_provider_providers.dart';
import 'ai_provider_edit_page.dart';

/// AI 供应商列表页面
class AiProvidersPage extends ConsumerWidget {
  const AiProvidersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(aiProviderListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 模型服务'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加供应商',
            onPressed: () => _navigateToEdit(context),
          ),
        ],
      ),
      body: providers.isEmpty
          ? _buildEmptyState(context, theme)
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: providers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _ProviderCard(
                  provider: providers[index],
                  onTap: () => _navigateToEdit(context, providers[index]),
                  onDelete: () =>
                      _confirmDelete(context, ref, providers[index]),
                );
              },
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.smart_toy_outlined,
              size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text('还没有配置 AI 供应商',
              style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text('添加供应商后可以使用 AI 助手功能',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _navigateToEdit(context),
            icon: const Icon(Icons.add),
            label: const Text('添加供应商'),
          ),
        ],
      ),
    );
  }

  void _navigateToEdit(BuildContext context, [AiProvider? provider]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiProviderEditPage(provider: provider),
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, AiProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除供应商「${provider.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              ref
                  .read(aiProviderListProvider.notifier)
                  .removeProvider(provider.id);
              Navigator.pop(ctx);
            },
            style:
                FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final AiProvider provider;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProviderCard({
    required this.provider,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabledCount = provider.models.where((m) => m.enabled).length;
    final totalCount = provider.models.length;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 图标
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _getTypeColor(provider.type).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.smart_toy_rounded,
                  color: _getTypeColor(provider.type),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              // 内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            provider.type.label,
                            style: theme.textTheme.labelSmall?.copyWith(
                                color:
                                    theme.colorScheme.onSecondaryContainer),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$enabledCount/$totalCount 个模型',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: theme.colorScheme.outline.withValues(alpha: 0.4),
                  size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Color _getTypeColor(AiProviderType type) {
    switch (type) {
      case AiProviderType.openai:
      case AiProviderType.openaiResponse:
        return Colors.green;
      case AiProviderType.gemini:
        return Colors.blue;
      case AiProviderType.anthropic:
        return Colors.orange;
    }
  }
}
