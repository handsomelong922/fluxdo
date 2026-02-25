import 'package:flutter/material.dart';

/// AI 聊天输入框
class AiChatInput extends StatefulWidget {
  final bool isGenerating;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;

  const AiChatInput({
    super.key,
    required this.isGenerating,
    required this.onSend,
    required this.onStop,
  });

  @override
  State<AiChatInput> createState() => _AiChatInputState();
}

class _AiChatInputState extends State<AiChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  bool get _canSend => _controller.text.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: 8 + bottomPadding,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: '输入消息...',
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLow,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 4),
          widget.isGenerating
              ? IconButton(
                  onPressed: widget.onStop,
                  icon: Icon(
                    Icons.stop_circle,
                    color: theme.colorScheme.error,
                  ),
                  tooltip: '停止生成',
                )
              : IconButton(
                  onPressed: _canSend ? _handleSend : null,
                  icon: Icon(
                    Icons.send_rounded,
                    color: _canSend
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  ),
                  tooltip: '发送',
                ),
        ],
      ),
    );
  }
}
