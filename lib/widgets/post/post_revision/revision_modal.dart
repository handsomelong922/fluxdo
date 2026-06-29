import 'package:flutter/material.dart';

import '../../../models/post_revision.dart';
import '../../../services/discourse/discourse_service.dart';
import '../../../utils/dialog_utils.dart';
import '../../../utils/responsive.dart';
import '../../../utils/time_utils.dart';
import '../../common/loading_spinner.dart';
import '../../content/discourse_html_content/discourse_html_content.dart';

Future<void> showPostRevisionSheet({
  required BuildContext context,
  required int postId,
  int? initialRevision,
  bool useRootNavigator = true,
}) async {
  if (Responsive.isMobile(context)) {
    await showAppBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      useRootNavigator: useRootNavigator,
      builder: (sheetContext) {
        final height = MediaQuery.sizeOf(sheetContext).height * 0.85;
        return SizedBox(
          height: height,
          child: _PostRevisionFrame(
            postId: postId,
            initialRevision: initialRevision,
          ),
        );
      },
    );
  } else {
    await showAppDialog<void>(
      context: context,
      useRootNavigator: useRootNavigator,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        final width = size.width.clamp(480.0, 880.0);
        final height = (size.height * 0.78).clamp(360.0, 720.0);
        return Dialog(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: SizedBox(
            width: width,
            height: height,
            child: _PostRevisionFrame(
              postId: postId,
              initialRevision: initialRevision,
            ),
          ),
        );
      },
    );
  }
}

class _PostRevisionFrame extends StatelessWidget {
  const _PostRevisionFrame({
    required this.postId,
    required this.initialRevision,
  });

  final int postId;
  final int? initialRevision;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
          child: Row(
            children: [
              Icon(
                Icons.history,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '编辑历史',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _PostRevisionView(
            postId: postId,
            initialRevision: initialRevision,
          ),
        ),
      ],
    );
  }
}

class _PostRevisionView extends StatefulWidget {
  const _PostRevisionView({required this.postId, this.initialRevision});

  final int postId;
  final int? initialRevision;

  @override
  State<_PostRevisionView> createState() => _PostRevisionViewState();
}

class _PostRevisionViewState extends State<_PostRevisionView> {
  final DiscourseService _service = DiscourseService();
  PostRevision? _revision;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load(widget.initialRevision);
  }

  Future<void> _load(int? revision) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = revision == null
          ? await _service.getLatestPostRevision(widget.postId)
          : await _service.getPostRevision(widget.postId, revision);
      if (!mounted) return;
      setState(() {
        _revision = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _revision == null) {
      return const Center(child: LoadingSpinner(size: 36));
    }

    if (_error != null && _revision == null) {
      return _RevisionErrorView(error: _error!, onRetry: () => _load(null));
    }

    final revision = _revision;
    if (revision == null) {
      return const Center(child: Text('暂无编辑历史'));
    }

    final bodyHtml =
        revision.bodyChanges?.inline ??
        revision.bodyChanges?.sideBySide ??
        revision.bodyChanges?.sideBySideMarkdown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RevisionToolbar(revision: revision, onNavigate: _load),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RevisionMeta(revision: revision),
                if (revision.titleChanges != null) ...[
                  const SizedBox(height: 12),
                  _SimpleChange(
                    label: '标题',
                    previous: revision.titleChanges!.previous,
                    current: revision.titleChanges!.current,
                  ),
                ],
                const SizedBox(height: 16),
                if (revision.diffError)
                  const Text('该版本差异解析失败，请稍后再试。')
                else if (bodyHtml == null || bodyHtml.isEmpty)
                  const Text('该版本没有正文差异。')
                else
                  DiscourseHtmlContent(html: bodyHtml, compact: true),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RevisionToolbar extends StatelessWidget {
  const _RevisionToolbar({required this.revision, required this.onNavigate});

  final PostRevision revision;
  final ValueChanged<int?> onNavigate;

  @override
  Widget build(BuildContext context) {
    final canPrevious = revision.currentRevision > 1;
    final nextRevision = revision.nextRevision;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: '上一版',
            onPressed: canPrevious
                ? () => onNavigate(revision.previousRevision)
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              '版本 ${revision.currentRevision} / ${revision.lastRevision}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          IconButton(
            tooltip: '下一版',
            onPressed: nextRevision == null
                ? null
                : () => onNavigate(nextRevision),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _RevisionMeta extends StatelessWidget {
  const _RevisionMeta({required this.revision});

  final PostRevision revision;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = revision.displayUsername?.isNotEmpty == true
        ? revision.displayUsername!
        : revision.username;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.55,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$name 编辑于 ${TimeUtils.formatDetailTime(revision.createdAt)}',
              style: theme.textTheme.bodySmall,
            ),
            if (revision.editReason != null) ...[
              const SizedBox(height: 6),
              Text(
                '原因：${revision.editReason!}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (revision.previousHidden || revision.currentHidden) ...[
              const SizedBox(height: 6),
              Text(
                '此版本包含隐藏状态变更',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SimpleChange extends StatelessWidget {
  const _SimpleChange({required this.label, this.previous, this.current});

  final String label;
  final String? previous;
  final String? current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Text('之前：${previous ?? '-'}'),
            const SizedBox(height: 4),
            Text('之后：${current ?? '-'}'),
          ],
        ),
      ),
    );
  }
}

class _RevisionErrorView extends StatelessWidget {
  const _RevisionErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('加载编辑历史失败：$error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
