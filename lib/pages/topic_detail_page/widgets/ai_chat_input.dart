import 'dart:convert';
import 'dart:io';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../l10n/s.dart';

/// 输入框 onSend 回调，携带文本和可选附件
typedef AiChatInputSend = void Function(
  String text,
  List<AiChatAttachment> attachments,
);

/// AI 聊天输入框
class AiChatInput extends StatefulWidget {
  final bool isGenerating;
  final AiChatInputSend onSend;
  final VoidCallback onStop;

  /// 是否启用图片附件功能（取决于当前模型是否支持多模态，UI 不强校验）
  final bool allowAttachments;

  /// 底部栏左侧额外控件（如模型选择器）
  final Widget? bottomLeading;

  const AiChatInput({
    super.key,
    required this.isGenerating,
    required this.onSend,
    required this.onStop,
    this.allowAttachments = true,
    this.bottomLeading,
  });

  @override
  State<AiChatInput> createState() => _AiChatInputState();
}

class _AiChatInputState extends State<AiChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _picker = ImagePicker();

  final List<AiChatAttachment> _pendingAttachments = [];

  bool get _canSend =>
      _controller.text.trim().isNotEmpty || _pendingAttachments.isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty && _pendingAttachments.isEmpty) return;
    final attachments = List<AiChatAttachment>.unmodifiable(_pendingAttachments);
    widget.onSend(text, attachments);
    _controller.clear();
    setState(_pendingAttachments.clear);
  }

  Future<void> _pickImage() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      final bytes = await File(picked.path).readAsBytes();
      setState(() {
        _pendingAttachments.add(AiChatAttachment(
          mimeType: _inferMimeType(picked.path),
          base64Data: base64Encode(bytes),
        ));
      });
    } catch (_) {
      // 用户取消或权限被拒，静默处理
    }
  }

  String _inferMimeType(String path) {
    final ext = path.toLowerCase().split('.').last;
    return switch (ext) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
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
          // 待发送附件预览
          if (_pendingAttachments.isNotEmpty) ...[
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _pendingAttachments.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final att = _pendingAttachments[index];
                  return _PendingAttachmentTile(
                    attachment: att,
                    onRemove: () =>
                        setState(() => _pendingAttachments.removeAt(index)),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
          ],
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
          // 底部栏：左侧放附件按钮 + 额外控件，右侧放发送/停止按钮
          Row(
            children: [
              if (widget.allowAttachments) ...[
                IconButton(
                  onPressed: widget.isGenerating ? null : _pickImage,
                  icon: const Icon(Icons.image_outlined, size: 20),
                  tooltip: context.l10n.ai_attachImageTooltip,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
              ],
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

/// 待发送附件的小卡片，右上角带删除按钮
class _PendingAttachmentTile extends StatelessWidget {
  final AiChatAttachment attachment;
  final VoidCallback onRemove;

  const _PendingAttachmentTile({
    required this.attachment,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: _buildPreview(64),
        ),
        Positioned(
          top: -4,
          right: -4,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview(double size) {
    final base64Data = attachment.base64Data;
    if (base64Data != null && base64Data.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(base64Data),
          width: size,
          height: size,
          fit: BoxFit.cover,
        );
      } catch (_) {/* fall through */}
    }
    final localPath = attachment.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      return Image.file(
        File(localPath),
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    }
    return Container(
      width: size,
      height: size,
      color: Colors.black12,
      child: const Icon(Icons.image_outlined),
    );
  }
}
