import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/export_history_item.dart';
import '../../models/topic.dart';
import '../../l10n/s.dart';
import '../../pages/notion_settings_page.dart';
import '../../providers/export_history_provider.dart';
import '../../providers/notion_config_provider.dart';
import '../../services/notion/notion_client.dart';
import '../../services/notion/notion_config.dart';
import '../../services/notion/notion_sync_service.dart';
import '../../services/toast_service.dart';
import '../../utils/dialog_utils.dart';
import '../../utils/export_utils.dart';
import '../../utils/share_utils.dart';

enum _ExportTarget { markdown, html, notion }

/// 导出选项 Sheet
class ExportSheet extends ConsumerStatefulWidget {
  /// 话题详情
  final TopicDetail detail;

  const ExportSheet({super.key, required this.detail});

  /// 显示导出 Sheet
  static Future<void> show(BuildContext context, TopicDetail detail) {
    return showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ExportSheet(detail: detail),
    );
  }

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<ExportSheet> {
  ExportScope _scope = ExportScope.firstPostOnly;
  _ExportTarget _target = _ExportTarget.markdown;
  bool _isExporting = false;
  int _progress = 0;
  int _total = 0;
  String? _phaseLabel;

  /// 获取话题的总帖子数
  int get _totalPostsCount => widget.detail.postStream.stream.length;

  /// 判断 Markdown 导出是否会被限制
  bool get _willBeLimited =>
      _target == _ExportTarget.markdown &&
      _scope == ExportScope.allPosts &&
      _totalPostsCount > ExportUtils.maxMarkdownPosts;

  Future<void> _export() async {
    if (_isExporting) return;
    setState(() {
      _isExporting = true;
      _progress = 0;
      _total = 0;
      _phaseLabel = null;
    });

    try {
      switch (_target) {
        case _ExportTarget.markdown:
        case _ExportTarget.html:
          await _exportLocal();
          break;
        case _ExportTarget.notion:
          await _exportNotion();
          break;
      }
    } catch (e) {
      if (mounted) {
        ToastService.showError(S.current.export_failed('$e'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _phaseLabel = null;
        });
      }
    }
  }

  Future<void> _exportLocal() async {
    final format = _target == _ExportTarget.markdown
        ? ExportFormat.markdown
        : ExportFormat.html;
    final result = await ExportUtils.exportTopic(
      detail: widget.detail,
      scope: _scope,
      format: format,
      onProgress: (current, total) {
        if (mounted) {
          setState(() {
            _progress = current;
            _total = total;
          });
        }
      },
    );
    if (result.shareOutcome.type != ShareOutcomeType.cancelled) {
      ref
          .read(exportHistoryProvider.notifier)
          .add(ExportHistoryItem.fromResult(result));
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _exportNotion() async {
    final config = ref.read(notionConfigProvider);
    if (!config.isComplete) {
      final goToSettings = await _askGoToSettings();
      if (goToSettings == true && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NotionSettingsPage()),
        );
      }
      return;
    }

    final service = NotionSyncService(config: config);
    final scope = _scope == ExportScope.firstPostOnly
        ? NotionSyncScope.firstPostOnly
        : NotionSyncScope.allPosts;

    Future<NotionSyncResult> run(DuplicateAction duplicateAction) {
      return service.syncTopic(
        detail: widget.detail,
        scope: scope,
        onDuplicate: duplicateAction,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _phaseLabel = _labelForPhase(progress);
            _progress = progress.current;
            _total = progress.total;
          });
        },
      );
    }

    NotionSyncResult result;
    try {
      result = await run(DuplicateAction.skip);
    } on NotionApiException catch (error) {
      throw Exception(error.message);
    }

    if (result.duplicated) {
      final action = await _askDuplicateAction();
      if (action == null) return;
      if (action == DuplicateAction.overwrite) {
        result = await run(DuplicateAction.overwrite);
      }
    }

    ref.read(exportHistoryProvider.notifier).add(_notionHistoryItem(result));
    if (mounted) {
      ToastService.showSuccess(S.current.notion_syncSucceed);
      Navigator.pop(context);
    }
  }

  ExportHistoryItem _notionHistoryItem(NotionSyncResult result) {
    final createdAt = DateTime.now();
    return ExportHistoryItem(
      id: '${createdAt.millisecondsSinceEpoch}-${widget.detail.id}-notion',
      topicId: widget.detail.id,
      topicTitle: widget.detail.title,
      topicSlug: widget.detail.slug,
      format: ExportFormat.notion,
      scope: _scope,
      postCount: result.postCount,
      byteSize: 0,
      destination: ShareOutcomeType.notion,
      createdAtMillis: createdAt.millisecondsSinceEpoch,
      filePath: result.pageUrl,
    );
  }

  String _labelForPhase(NotionSyncProgress progress) {
    switch (progress.phase) {
      case SyncPhase.fetch:
        return progress.total > 0
            ? S.current.notion_syncingFetch(progress.current, progress.total)
            : S.current.notion_syncing;
      case SyncPhase.convert:
        return S.current.notion_syncingConvert;
      case SyncPhase.create:
        return S.current.notion_syncingCreate;
      case SyncPhase.append:
        return S.current.notion_syncingAppend(progress.current, progress.total);
      case SyncPhase.done:
        return S.current.notion_syncing;
    }
  }

  Future<bool?> _askGoToSettings() {
    return showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.current.notion_title),
        content: Text(S.current.notion_notConfigured),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.current.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(S.current.common_confirm),
          ),
        ],
      ),
    );
  }

  Future<DuplicateAction?> _askDuplicateAction() {
    return showAppDialog<DuplicateAction?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.current.notion_duplicateTitle),
        content: Text(S.current.notion_duplicateMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(S.current.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, DuplicateAction.skip),
            child: Text(S.current.notion_duplicateSkip),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, DuplicateAction.overwrite),
            child: Text(S.current.notion_duplicateOverwrite),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    ref.watch(notionConfigProvider);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部拖动条
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // 标题
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                context.l10n.export_title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 导出范围选择
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                context.l10n.export_range,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<ExportScope>(
                segments: [
                  ButtonSegment(
                    value: ExportScope.firstPostOnly,
                    label: Text(context.l10n.export_firstPostOnly),
                    icon: const Icon(Icons.article_outlined),
                  ),
                  ButtonSegment(
                    value: ExportScope.allPosts,
                    label: Text(context.l10n.common_all),
                    icon: const Icon(Icons.forum_outlined),
                  ),
                ],
                selected: {_scope},
                onSelectionChanged: (selected) {
                  setState(() => _scope = selected.first);
                },
              ),
            ),

            const SizedBox(height: 20),

            // 导出格式选择
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                context.l10n.export_format,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<_ExportTarget>(
                segments: const [
                  ButtonSegment(
                    value: _ExportTarget.markdown,
                    label: Text('MD'),
                    icon: Icon(Icons.code),
                  ),
                  ButtonSegment(
                    value: _ExportTarget.html,
                    label: Text('HTML'),
                    icon: Icon(Icons.html),
                  ),
                  ButtonSegment(
                    value: _ExportTarget.notion,
                    label: Text('Notion'),
                    icon: Icon(Icons.cloud_sync_rounded),
                  ),
                ],
                selected: {_target},
                onSelectionChanged: (selected) {
                  setState(() => _target = selected.first);
                },
              ),
            ),

            // Markdown 限制提示
            if (_willBeLimited) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        context.l10n.export_markdownLimit(
                          ExportUtils.maxMarkdownPosts,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // 导出按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                onPressed: _isExporting ? null : _export,
                icon: _isExporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download),
                label: Text(
                  _isExporting
                      ? (_phaseLabel ??
                            (_total > 0
                                ? context.l10n.export_exporting(
                                    _progress,
                                    _total,
                                  )
                                : context.l10n.export_exportingNoProgress))
                      : context.l10n.common_export,
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            SizedBox(height: 16 + bottomPadding),
          ],
        ),
      ),
    );
  }
}
