import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';

import '../../../widgets/markdown_editor/markdown_renderer.dart';

/// AI 聊天消息气泡
class AiChatMessageItem extends StatelessWidget {
  final AiChatMessage message;
  final VoidCallback? onRetry;

  const AiChatMessageItem({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    return isUser ? _buildUserMessage(context) : _buildAssistantMessage(context);
  }

  Widget _buildUserMessage(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.only(left: 48, right: 16, top: 4, bottom: 4),
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

  Widget _buildAssistantMessage(BuildContext context) {
    final theme = Theme.of(context);
    final isStreaming = message.status == MessageStatus.streaming;
    final isError = message.status == MessageStatus.error;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        margin: const EdgeInsets.only(left: 16, right: 48, top: 4, bottom: 4),
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
              // 纯错误状态
              _buildErrorWidget(context),
            ] else ...[
              // 正常内容或带内容的错误
              if (message.content.isNotEmpty)
                MarkdownBody(data: '${message.content}${isStreaming ? ' ▊' : ''}'),
              if (message.content.isEmpty && isStreaming)
                _buildStreamingIndicator(context),
              if (isError && message.content.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildErrorWidget(context),
              ],
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
                message.errorMessage ?? '生成失败',
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
                '重试',
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
}
