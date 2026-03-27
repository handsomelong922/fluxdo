import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_provider.dart';
import '../providers/ai_chat_providers.dart';
import '../providers/ai_provider_providers.dart';
import '../services/ai_chat_storage_service.dart';
import '../l10n/ai_l10n.dart';
import '../utils/dialog_utils.dart';
import '../widgets/swipe_action_cell.dart';
import 'ai_chat_history_page.dart';
import 'ai_provider_edit_page.dart';

/// AI 供应商列表页面
class AiProvidersPage extends ConsumerWidget {
  /// 点击会话时的回调，由外部实现导航逻辑
  final OpenSessionCallback? onOpenSession;

  const AiProvidersPage({super.key, this.onOpenSession});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(aiProviderListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(AiL10n.current.aiModelService),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: AiL10n.current.addProvider,
            onPressed: () => _navigateToEdit(context),
          ),
        ],
      ),
      body: providers.isEmpty
          ? _buildEmptyState(context, theme)
          : SwipeActionScope(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 供应商列表
                  ...List.generate(providers.length, (index) {
                    final provider = providers[index];
                    return Padding(
                      padding: EdgeInsets.only(
                          bottom: index < providers.length - 1 ? 12 : 0),
                      child: SwipeActionCell(
                        key: ValueKey(provider.id),
                        trailingActions: [
                          SwipeAction(
                            icon: Icons.edit_outlined,
                            color: Colors.blue,
                            label: AiL10n.current.edit,
                            onPressed: () =>
                                _navigateToEdit(context, provider),
                          ),
                          SwipeAction(
                            icon: Icons.delete_outline,
                            color: Colors.red,
                            label: AiL10n.current.delete,
                            onPressed: () =>
                                _confirmDelete(context, ref, provider),
                          ),
                        ],
                        child: _ProviderCard(
                          provider: provider,
                          onTap: () =>
                              _navigateToEdit(context, provider),
                        ),
                      ),
                    );
                  }),
                  // 网络设置
                  const SizedBox(height: 24),
                  _NetworkSettingsSection(ref: ref),
                  // 聊天设置
                  const SizedBox(height: 24),
                  _ChatSettingsSection(
                      ref: ref, onOpenSession: onOpenSession),
                ],
              ),
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
          Text(AiL10n.current.noProviderConfigured,
              style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(AiL10n.current.addProviderHint,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _navigateToEdit(context),
            icon: const Icon(Icons.add),
            label: Text(AiL10n.current.addProvider),
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
    showAppDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AiL10n.current.confirmDelete),
        content: Text(AiL10n.current.confirmDeleteProvider(provider.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AiL10n.current.cancel),
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
            child: Text(AiL10n.current.delete),
          ),
        ],
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final AiProvider provider;
  final VoidCallback onTap;

  const _ProviderCard({
    required this.provider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabledCount = provider.models.where((m) => m.enabled).length;
    final totalCount = provider.models.length;

    // 不包 Card，由外层 SwipeActionCell 提供容器
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
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
                        AiL10n.current.modelCount(enabledCount, totalCount),
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

/// 聊天设置区域
class _ChatSettingsSection extends StatelessWidget {
  final WidgetRef ref;
  final OpenSessionCallback? onOpenSession;

  const _ChatSettingsSection({required this.ref, this.onOpenSession});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final storageService = ref.watch(aiChatStorageServiceProvider);
    final maxSessions = storageService.getMaxSessions();
    final totalCount = storageService.getTotalSessionCount();

    // 标题生成模型
    final allModels = ref.watch(allAvailableAiModelsProvider);
    final titleModel = ref.watch(aiTitleModelProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            AiL10n.current.chatHistory,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              // 标题生成模型
              _SettingRow(
                title: AiL10n.current.titleGenerationModel,
                subtitle: AiL10n.current.autoGenerateTitleSubtitle,
                trailing: GestureDetector(
                  onTap: () => _showTitleModelPicker(
                      context, allModels, titleModel),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 80),
                          child: Text(
                            titleModel != null
                                ? (titleModel.model.name ??
                                    titleModel.model.id)
                                : AiL10n.current.notSet,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.unfold_more,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              // 最大会话记录数
              _SettingRow(
                title: AiL10n.current.maxSessionCount,
                subtitle: AiL10n.current.autoDeleteOldestSession,
                trailing: GestureDetector(
                  onTap: () =>
                      _showMaxSessionsPicker(context, storageService, maxSessions),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$maxSessions',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              // 会话记录管理
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        AiChatHistoryPage(onOpenSession: onOpenSession),
                  ),
                ),
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12)),
                child: _SettingRow(
                  title: AiL10n.current.sessionManagement,
                  subtitle: AiL10n.current.totalSessionCount(totalCount),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: theme.colorScheme.outline.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showTitleModelPicker(
    BuildContext context,
    List<({AiProvider provider, AiModel model})> allModels,
    ({AiProvider provider, AiModel model})? current,
  ) {
    showAppBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              ListTile(
                title: Text(AiL10n.current.noAutoGenerateTitle),
                trailing: current == null ? const Icon(Icons.check) : null,
                onTap: () {
                  setAiTitleModel(ref, null, null);
                  Navigator.pop(ctx);
                  (context as Element).markNeedsBuild();
                },
              ),
              ...allModels.map((item) {
                final isCurrent = current != null &&
                    item.provider.id == current.provider.id &&
                    item.model.id == current.model.id;
                return ListTile(
                  title: Text(item.model.name ?? item.model.id),
                  subtitle: Text(item.provider.name),
                  trailing: isCurrent ? const Icon(Icons.check) : null,
                  onTap: () {
                    setAiTitleModel(
                        ref, item.provider.id, item.model.id);
                    Navigator.pop(ctx);
                    (context as Element).markNeedsBuild();
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showMaxSessionsPicker(
    BuildContext context,
    AiChatStorageService storageService,
    int currentValue,
  ) {
    final options = [10, 20, 30, 50, 100, 200];

    showAppBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              ...options.map((value) => ListTile(
                    title: Text('$value'),
                    trailing:
                        value == currentValue ? const Icon(Icons.check) : null,
                    onTap: () {
                      storageService.setMaxSessions(value);
                      Navigator.pop(ctx);
                      (context as Element).markNeedsBuild();
                    },
                  )),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

/// 网络设置区域
class _NetworkSettingsSection extends StatelessWidget {
  final WidgetRef ref;

  const _NetworkSettingsSection({required this.ref});

  @override
  Widget build(BuildContext context) {
    final useAppNetwork = ref.watch(aiUseAppNetworkProvider);
    final hasAdapterFactory = ref.watch(aiDioAdapterFactoryProvider) != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: SwitchListTile(
        title: Text(AiL10n.current.useAppNetwork),
        subtitle: Text(AiL10n.current.useAppNetworkSubtitle),
        value: useAppNetwork && hasAdapterFactory,
        onChanged: hasAdapterFactory
            ? (value) async {
                final prefs = ref.read(aiSharedPreferencesProvider);
                await prefs.setBool('ai_use_app_network', value);
                ref.read(aiUseAppNetworkProvider.notifier).state = value;
              }
            : null,
      ),
    );
  }
}

/// 设置行通用组件
class _SettingRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget trailing;

  const _SettingRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}
