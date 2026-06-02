import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:popover/popover.dart';

import '../../providers/ai_post_review_provider.dart';
import '../../services/ai_post_review_service.dart';
import '../../services/toast_service.dart';
import '../../utils/dialog_utils.dart';

class AiPostReviewInputSnapshot {
  const AiPostReviewInputSnapshot({
    required this.target,
    required this.title,
    required this.content,
    required this.categoryName,
    required this.categoryDescription,
    required this.tags,
  });

  final AiPostReviewTarget target;
  final String? title;
  final String content;
  final String? categoryName;
  final String? categoryDescription;
  final List<String> tags;

  bool get hasContent => content.trim().isNotEmpty;

  bool hasSameSignature(AiPostReviewInputSnapshot other) {
    return signature == other.signature;
  }

  String get signature {
    final normalizedTags =
        tags
            .map(_normalize)
            .where((tag) => tag.isNotEmpty)
            .toList(growable: false)
          ..sort();
    return [
      target.name,
      _normalize(title),
      _normalizeContent(content),
      _normalize(categoryName),
      _normalize(categoryDescription),
      normalizedTags.join(','),
    ].join('\u001f');
  }

  static String _normalize(String? value) {
    return (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _normalizeContent(String value) {
    return value.replaceAll(RegExp(r'\r\n?'), '\n').trim();
  }
}

class _CachedAiPostReview {
  const _CachedAiPostReview({
    required this.result,
    required this.snapshot,
    required this.modelLabel,
  });

  final AiPostReviewResult result;
  final AiPostReviewInputSnapshot snapshot;
  final String modelLabel;
}

enum _ChangedContentAction { reviewCurrent, viewLast }

class AiPostReviewButton extends ConsumerStatefulWidget {
  const AiPostReviewButton({
    super.key,
    required this.titleBuilder,
    required this.contentBuilder,
    required this.target,
    this.enabled = true,
    this.categoryNameBuilder,
    this.categoryDescriptionBuilder,
    this.tagsBuilder,
  });

  final String? Function() titleBuilder;
  final String Function() contentBuilder;
  final AiPostReviewTarget target;
  final bool enabled;
  final String? Function()? categoryNameBuilder;
  final String? Function()? categoryDescriptionBuilder;
  final List<String> Function()? tagsBuilder;

  @override
  ConsumerState<AiPostReviewButton> createState() => _AiPostReviewButtonState();
}

class _AiPostReviewButtonState extends ConsumerState<AiPostReviewButton> {
  bool _isReviewing = false;
  _CachedAiPostReview? _cachedReview;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (anchorContext) => TextButton.icon(
        onPressed: _isReviewing || !widget.enabled
            ? null
            : () => _runReview(anchorContext),
        icon: _isReviewing
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            : const Icon(Icons.fact_check_outlined, size: 18),
        label: Text(_isReviewing ? '审核中' : 'AI 审核'),
      ),
    );
  }

  Future<void> _runReview(
    BuildContext anchorContext, {
    bool forceReview = false,
  }) async {
    final snapshot = _buildSnapshot();
    final cached = _cachedReview;
    if (!forceReview && cached != null) {
      if (cached.snapshot.hasSameSignature(snapshot)) {
        unawaited(
          _showReviewResult(
            anchorContext,
            cached,
            isStaleForCurrentInput: false,
          ),
        );
        return;
      }

      final action = await _showChangedContentChoice();
      if (!mounted || !anchorContext.mounted || action == null) return;
      if (action == _ChangedContentAction.viewLast) {
        unawaited(
          _showReviewResult(
            anchorContext,
            cached,
            isStaleForCurrentInput: true,
          ),
        );
        return;
      }
    }

    if (!snapshot.hasContent) {
      ToastService.showInfo('请先输入正文内容');
      return;
    }

    final selected = ref.read(aiPostReviewSelectedModelProvider);
    if (selected == null) {
      ToastService.showInfo('请先在 AI 设置中配置可用模型');
      return;
    }

    setState(() => _isReviewing = true);
    try {
      final service = ref.read(aiPostReviewServiceProvider);
      final result = await service.review(
        AiPostReviewRequest(
          provider: selected.provider,
          model: selected.model,
          title: snapshot.title,
          content: snapshot.content.trim(),
          target: snapshot.target,
          categoryName: snapshot.categoryName,
          categoryDescription: snapshot.categoryDescription,
          tags: List.unmodifiable(snapshot.tags),
        ),
      );
      if (!mounted) return;
      final nextCache = _CachedAiPostReview(
        result: result,
        snapshot: snapshot,
        modelLabel: _modelLabel(selected),
      );
      final isStaleForCurrentInput = !snapshot.hasSameSignature(
        _buildSnapshot(),
      );
      setState(() => _cachedReview = nextCache);
      if (!anchorContext.mounted) return;
      unawaited(
        _showReviewResult(
          anchorContext,
          nextCache,
          isStaleForCurrentInput: isStaleForCurrentInput,
        ),
      );
    } on AiPostReviewException catch (error) {
      if (!mounted) return;
      _showReviewError(error.message, details: error.details);
    } catch (error, stackTrace) {
      if (!mounted) return;
      _showReviewError('AI 审核失败，请稍后重试。', details: '$error\n$stackTrace');
    } finally {
      if (mounted) setState(() => _isReviewing = false);
    }
  }

  AiPostReviewInputSnapshot _buildSnapshot() {
    return AiPostReviewInputSnapshot(
      target: widget.target,
      title: widget.titleBuilder(),
      content: widget.contentBuilder(),
      categoryName: widget.categoryNameBuilder?.call(),
      categoryDescription: widget.categoryDescriptionBuilder?.call(),
      tags: List.unmodifiable(widget.tagsBuilder?.call() ?? const []),
    );
  }

  String _modelLabel(({AiProvider provider, AiModel model}) selected) {
    final modelName = selected.model.name?.trim().isNotEmpty == true
        ? selected.model.name!.trim()
        : selected.model.id;
    return '${selected.provider.name} / $modelName';
  }

  Future<_ChangedContentAction?> _showChangedContentChoice() {
    return showAppDialog<_ChangedContentAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('内容已变更'),
        content: const Text('当前内容和上次审核时不同，要重新审核当前内容，还是查看上次结果？'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _ChangedContentAction.viewLast),
            child: const Text('查看上次结果'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _ChangedContentAction.reviewCurrent,
            ),
            child: const Text('审核当前内容'),
          ),
        ],
      ),
    );
  }

  Future<void> _showReviewResult(
    BuildContext anchorContext,
    _CachedAiPostReview cached, {
    required bool isStaleForCurrentInput,
  }) {
    final theme = Theme.of(anchorContext);
    return showPopover(
      context: anchorContext,
      bodyBuilder: (popoverContext) => _AiPostReviewPopover(
        cached: cached,
        isStaleForCurrentInput: isStaleForCurrentInput,
        onReviewAgain: () async {
          Navigator.of(popoverContext).pop();
          await Future<void>.delayed(Duration.zero);
          if (!mounted || !anchorContext.mounted) return;
          await _runReview(anchorContext, forceReview: true);
        },
      ),
      direction: PopoverDirection.bottom,
      arrowHeight: 8,
      arrowWidth: 12,
      backgroundColor: theme.colorScheme.surface,
      barrierColor: Colors.transparent,
      radius: 8,
      shadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.15),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  void _showReviewError(String message, {String? details}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      ToastService.showInfo(message);
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: details == null || details.isEmpty
              ? null
              : SnackBarAction(
                  label: '复制详情',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: details));
                    ToastService.showInfo('错误详情已复制');
                  },
                ),
        ),
      );
  }
}

class _AiPostReviewPopover extends StatelessWidget {
  const _AiPostReviewPopover({
    required this.cached,
    required this.isStaleForCurrentInput,
    required this.onReviewAgain,
  });

  final _CachedAiPostReview cached;
  final bool isStaleForCurrentInput;
  final Future<void> Function() onReviewAgain;

  @override
  Widget build(BuildContext context) {
    final result = cached.result;
    final tone = _toneFor(result.level);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360, maxHeight: 500),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _LevelHeader(tone: tone, levelText: _levelText(result.level)),
            const SizedBox(height: 10),
            _ModelInfoRow(modelLabel: cached.modelLabel),
            if (isStaleForCurrentInput) ...[
              const SizedBox(height: 10),
              const _NoticeBox(
                icon: Icons.history_rounded,
                text: '这是上次内容的审核结果',
              ),
            ],
            if (result.usedCachedGuidelines) ...[
              const SizedBox(height: 12),
              const _NoticeBox(
                icon: Icons.info_outline_rounded,
                text: '本次使用了已缓存的社区准则',
              ),
            ],
            const SizedBox(height: 14),
            _SuggestionList(items: result.suggestions, tone: tone),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onReviewAgain,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重新审核'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _ReviewTone _toneFor(AiPostReviewLevel level) {
    return switch (level) {
      AiPostReviewLevel.low => const _ReviewTone(
        color: Color(0xFF2E7D32),
        icon: Icons.check_circle_outline_rounded,
      ),
      AiPostReviewLevel.medium => const _ReviewTone(
        color: Color(0xFFF57C00),
        icon: Icons.error_outline_rounded,
      ),
      AiPostReviewLevel.high => const _ReviewTone(
        color: Color(0xFFC62828),
        icon: Icons.warning_amber_rounded,
      ),
    };
  }

  String _levelText(AiPostReviewLevel level) {
    return switch (level) {
      AiPostReviewLevel.low => '低风险',
      AiPostReviewLevel.medium => '建议调整',
      AiPostReviewLevel.high => '高风险',
    };
  }
}

class _ModelInfoRow extends StatelessWidget {
  const _ModelInfoRow({required this.modelLabel});

  final String modelLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          Icons.smart_toy_outlined,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '模型：$modelLabel',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewTone {
  const _ReviewTone({required this.color, required this.icon});

  final Color color;
  final IconData icon;
}

class _LevelHeader extends StatelessWidget {
  const _LevelHeader({required this.tone, required this.levelText});

  final _ReviewTone tone;
  final String levelText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.color.withValues(alpha: 0.10),
        border: Border.all(color: tone.color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(tone.icon, size: 20, color: tone.color),
          const SizedBox(width: 8),
          Text(
            '审核等级',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: tone.color,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              levelText,
              style: theme.textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.items, required this.tone});

  final List<String> items;
  final _ReviewTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0)
            Divider(
              height: 18,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tone.color,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SelectableText(
                    items[index],
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
