import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../models/export_history_item.dart';
import '../providers/export_history_provider.dart';
import '../services/toast_service.dart';
import '../utils/export_utils.dart';
import '../utils/share_utils.dart';
import '../utils/time_utils.dart';

class ExportHistoryPage extends ConsumerWidget {
  const ExportHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(exportHistoryProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('导出历史'),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: '清空',
              onPressed: () => _confirmClear(context, ref),
            ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history_edu_rounded,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无导出记录',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = items[index];
                return _ExportHistoryCard(
                  item: item,
                  onOpen: () => _openItem(item),
                  onDelete: () =>
                      ref.read(exportHistoryProvider.notifier).remove(item.id),
                );
              },
            ),
    );
  }

  Future<void> _openItem(ExportHistoryItem item) async {
    final path = item.filePath;
    if (path == null || path.isEmpty) {
      ToastService.show('该记录来自系统分享，没有本地保存路径');
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      ToastService.showError('文件不存在');
      return;
    }
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      await ShareUtils.shareOrSaveFile(XFile(path));
    }
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空导出历史'),
        content: const Text('确定要清空全部导出记录吗？文件本身不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(exportHistoryProvider.notifier).clearAll();
              Navigator.pop(ctx);
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}

class _ExportHistoryCard extends StatelessWidget {
  const _ExportHistoryCard({
    required this.item,
    required this.onOpen,
    required this.onDelete,
  });

  final ExportHistoryItem item;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPath = item.filePath != null && item.filePath!.isNotEmpty;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hasPath ? onOpen : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  item.format == ExportFormat.markdown
                      ? Icons.code_rounded
                      : Icons.html_rounded,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.topicTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        item.format.displayName,
                        item.scope == ExportScope.firstPostOnly
                            ? '仅主帖'
                            : '全部帖子',
                        '${item.postCount} 帖',
                        _formatBytes(item.byteSize),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      TimeUtils.formatDetailTime(item.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (hasPath) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.filePath!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: '删除记录',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}
