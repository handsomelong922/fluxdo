import 'package:flutter/material.dart';
import '../../../l10n/s.dart';

/// AI 聊天输入框
class AiChatInput extends StatefulWidget {
  final bool isGenerating;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;

  /// 底部栏左侧额外控件（如模型选择器）
  final Widget? bottomLeading;

  const AiChatInput({
    super.key,
    required this.isGenerating,
    required this.onSend,
    required this.onStop,
    this.bottomLeading,
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
        bottom: 4 + bottomPadding,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 输入框
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            maxLines: 5,
            minLines: 1,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: context.l10n.ai_inputHint,
              hintStyle: TextStyle(
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.5),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              isDense: true,
              filled: true,
              fillColor: theme.colorScheme.surface,
              hoverColor: Colors.transparent,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),
          // 底部栏：左侧放额外控件，右侧放发送/停止按钮
          Row(
            children: [
              if (widget.bottomLeading != null) widget.bottomLeading!,
              const Spacer(),
              widget.isGenerating
                  ? IconButton.filled(
                      onPressed: widget.onStop,
                      icon: const Icon(Icons.stop_rounded, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.errorContainer,
                        foregroundColor: theme.colorScheme.onErrorContainer,
                        minimumSize: const Size(36, 36),
                        padding: EdgeInsets.zero,
                      ),
                      tooltip: context.l10n.ai_stopGenerate,
                    )
                  : IconButton.filled(
                      onPressed: _canSend ? _handleSend : null,
                      icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: _canSend
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.1),
                        foregroundColor: _canSend
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.4),
                        minimumSize: const Size(36, 36),
                        padding: EdgeInsets.zero,
                      ),
                      tooltip: context.l10n.ai_sendTooltip,
                    ),
            ],
          ),
        ],
      ),
    );
  }
}
