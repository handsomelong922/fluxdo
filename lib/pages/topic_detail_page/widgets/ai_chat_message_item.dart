import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';
import '../../../l10n/s.dart';

import '../../../widgets/markdown_editor/markdown_renderer.dart';

/// AI 聊天消息气泡
class AiChatMessageItem extends StatelessWidget {
  final AiChatMessage message;
  final VoidCallback? onRetry;
  final VoidCallback? onShareAsImage;
  final VoidCallback? onCopyText;

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

    return isUser ? _buildUserMessage(context) : _buildAssistantMessage(context);
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

  Widget _buildUserMessage(BuildContext context, {bool inSelectionMode = false}) {
    final theme = Theme.of(context);

    return Align(
      alignment: inSelectionMode ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: inSelectionMode
              ? double.infinity
              : MediaQuery.of(context).size.width * 0.78,
        ),
        margin: inSelectionMode
            ? const EdgeInsets.only(top: 4, bottom: 4)
            : const EdgeInsets.only(left: 48, right: 16, top: 4, bottom: 4),
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

  Widget _buildAssistantMessage(BuildContext context, {bool inSelectionMode = false}) {
    final theme = Theme.of(context);
    final isStreaming = message.status == MessageStatus.streaming;
    final isError = message.status == MessageStatus.error;
    final isCompleted = message.status == MessageStatus.completed;
    final hasContent = message.content.isNotEmpty;
    final showActions = isCompleted && hasContent && !inSelectionMode;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: inSelectionMode
              ? double.infinity
              : MediaQuery.of(context).size.width * 0.85,
        ),
        margin: inSelectionMode
            ? const EdgeInsets.only(top: 4, bottom: 4)
            : const EdgeInsets.only(left: 16, right: 48, top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                MarkdownBody(data: '${message.content}${isStreaming ? ' ▊' : ''}'),
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
              _buildActionBar(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStreamingIndicator(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      '▊',
      style: TextStyle(
        color: theme.colorScheme.primary,
        fontSize: 16,
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
              icon: Icon(Icons.refresh, size: 14, color: theme.colorScheme.primary),
              label: Text(
                context.l10n.ai_retryLabel,
                style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
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
            Text(
              label,
              style: TextStyle(fontSize: 11, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
