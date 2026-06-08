import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';
import '../../../l10n/s.dart';
import '../../../utils/link_launcher.dart';

import '../../../widgets/markdown_editor/markdown_renderer.dart';

/// AI 聊天消息气泡
class AiChatMessageItem extends StatelessWidget {
  final AiChatMessage message;
  final VoidCallback? onRetry;
  final VoidCallback? onShareAsImage;
  final VoidCallback? onCopyText;
  final InternalTopicLinkTap? onInternalLinkTap;

  /// 多选模式相关
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onSelectionToggle;

  const AiChatMessageItem({
    super.key,
    required this.message,
    this.onRetry,
    this.onShareAsImage,
    this.onCopyText,
    this.onInternalLinkTap,
    this.selectionMode = false,
    this.isSelected = false,
    this.onSelectionToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;

    if (selectionMode) {
      return _buildSelectableMessage(context, isUser);
    }

    return isUser
        ? _buildUserMessage(context)
        : _buildAssistantMessage(context);
  }

  /// 多选模式下的消息
  Widget _buildSelectableMessage(BuildContext context, bool isUser) {
    return InkWell(
      onTap: onSelectionToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Checkbox(
                value: isSelected,
                onChanged: (_) => onSelectionToggle?.call(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            Expanded(
              child: Opacity(
                opacity: isSelected ? 1.0 : 0.6,
                child: isUser
                    ? _buildUserMessage(context, inSelectionMode: true)
                    : _buildAssistantMessage(context, inSelectionMode: true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserMessage(
    BuildContext context, {
    bool inSelectionMode = false,
  }) {
    final theme = Theme.of(context);

    return Align(
      alignment: inSelectionMode ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: inSelectionMode
              ? double.infinity
              : MediaQuery.of(context).size.width * 0.86,
        ),
        margin: inSelectionMode
            ? const EdgeInsets.only(top: 4, bottom: 4)
            : const EdgeInsets.only(left: 28, right: 8, top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: SelectableText(
          message.content,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantMessage(
    BuildContext context, {
    bool inSelectionMode = false,
  }) {
    final theme = Theme.of(context);
    final isStreaming = message.status == MessageStatus.streaming;
    final isError = message.status == MessageStatus.error;
    final isCompleted = message.status == MessageStatus.completed;
    final hasContent = message.content.isNotEmpty;
    final showActions = isCompleted && hasContent && !inSelectionMode;
    final markdownContent = _displayMarkdownContent(isStreaming: isStreaming);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: inSelectionMode
              ? double.infinity
              : MediaQuery.of(context).size.width * 0.96,
        ),
        margin: inSelectionMode
            ? const EdgeInsets.only(top: 4, bottom: 4)
            : const EdgeInsets.only(left: 8, right: 8, top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isError && message.content.isEmpty) ...[
              _buildErrorWidget(context),
            ] else ...[
              if (message.content.isNotEmpty)
                MarkdownBody(
                  data: markdownContent,
                  onInternalLinkTap: onInternalLinkTap,
                ),
              if (message.content.isEmpty && isStreaming)
                _buildStreamingIndicator(context),
              if (isError && message.content.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildErrorWidget(context),
              ],
            ],
            // 操作按钮行
            if (showActions) ...[
              const SizedBox(height: 8),
              if (_hasTokenUsage) ...[
                _buildTokenUsage(context),
                const SizedBox(height: 6),
              ],
              _buildActionBar(context),
            ],
          ],
        ),
      ),
    );
  }

  String _displayMarkdownContent({required bool isStreaming}) {
    final content = _stripWrappingMarkdownFence(
      message.content,
      allowOpenFence: isStreaming,
    );
    return isStreaming ? '$content ▊' : content;
  }

  String _stripWrappingMarkdownFence(
    String raw, {
    required bool allowOpenFence,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return raw;

    final closedFence = RegExp(
      r'^```([^\r\n`]*)\r?\n([\s\S]*?)\r?\n```\s*$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (closedFence != null) {
      final language = closedFence.group(1)?.trim().toLowerCase() ?? '';
      final body = closedFence.group(2) ?? '';
      if (_shouldUnwrapFence(language, body)) {
        return body.trim();
      }
    }

    if (allowOpenFence) {
      final openFence = RegExp(
        r'^```([^\r\n`]*)\r?\n([\s\S]*)$',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (openFence != null && !trimmed.endsWith('```')) {
        final language = openFence.group(1)?.trim().toLowerCase() ?? '';
        final body = openFence.group(2) ?? '';
        if (_shouldUnwrapFence(language, body)) {
          return body.trimRight();
        }
      }
    }

    return raw;
  }

  bool _shouldUnwrapFence(String language, String body) {
    if (language == 'markdown' || language == 'md') {
      return true;
    }
    if (language.isNotEmpty) return false;
    return _looksLikeMarkdownDocument(body);
  }

  bool _looksLikeMarkdownDocument(String body) {
    return RegExp(
      r'(^|\n)\s{0,3}(#{1,6}\s|\*{1,2}[^*\n]+\*{1,2}|[-*+]\s+|\d+\.\s+|>\s+)',
    ).hasMatch(body);
  }

  Widget _buildStreamingIndicator(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      '▊',
      style: TextStyle(color: theme.colorScheme.primary, fontSize: 16),
    );
  }

  bool get _hasTokenUsage =>
      message.promptTokens != null ||
      message.responseTokens != null ||
      message.cachedTokens != null;

  Widget _buildTokenUsage(BuildContext context) {
    final theme = Theme.of(context);
    final prompt = message.promptTokens ?? 0;
    final response = message.responseTokens ?? 0;
    final cached = message.cachedTokens ?? 0;
    final text = cached > 0
        ? 'tokens $prompt/$response · cached $cached'
        : 'tokens $prompt/$response';
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        fontSize: 11,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );
  }

  Widget _buildErrorWidget(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                message.errorMessage ?? context.l10n.ai_generateFailed,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 28,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: Icon(
                Icons.refresh,
                size: 14,
                color: theme.colorScheme.primary,
              ),
              label: Text(
                context.l10n.ai_retryLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 操作按钮行
  Widget _buildActionBar(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: Icons.image_outlined,
          label: context.l10n.ai_exportImage,
          color: color,
          onTap: onShareAsImage,
        ),
        const SizedBox(width: 12),
        _ActionButton(
          icon: Icons.copy_outlined,
          label: context.l10n.ai_copyLabel,
          color: color,
          onTap: onCopyText,
        ),
      ],
    );
  }
}

/// 紧凑的操作按钮
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}
