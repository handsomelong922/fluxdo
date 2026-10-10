import 'package:flutter/material.dart';

import '../../l10n/s.dart';

/// 标题取色沿用主题设置的 HEX 输入方式，仅支持不透明 RGB。
class TopicTitleColorDialog extends StatefulWidget {
  const TopicTitleColorDialog({super.key, required this.initialColor});

  final int initialColor;

  @override
  State<TopicTitleColorDialog> createState() => _TopicTitleColorDialogState();
}

class _TopicTitleColorDialogState extends State<TopicTitleColorDialog> {
  static const _palette = [
    0xFF212121,
    0xFFF5F5F5,
    0xFF1565C0,
    0xFF64B5F6,
    0xFF2E7D32,
    0xFF81C784,
    0xFFAD1457,
    0xFFF06292,
    0xFF6A1B9A,
    0xFFBA68C8,
    0xFFBF360C,
    0xFFFFB74D,
  ];
  late final TextEditingController _controller;
  int? _color;

  String _hex(int color) => color.toRadixString(16).substring(2).toUpperCase();

  @override
  void initState() {
    super.initState();
    _color = widget.initialColor;
    _controller = TextEditingController(text: _hex(widget.initialColor));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final color = Color(_color ?? widget.initialColor);
    final foreground = color.computeLuminance();
    final background = scheme.surface.computeLuminance();
    final contrast = (foreground > background)
        ? (foreground + 0.05) / (background + 0.05)
        : (background + 0.05) / (foreground + 0.05);
    return AlertDialog(
      title: Text(l10n.topicCardStyle_titleColor),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final value in _palette)
                    Semantics(
                      label: '#${_hex(value)}',
                      selected: _color == value,
                      button: true,
                      child: Tooltip(
                        message: '#${_hex(value)}',
                        child: InkWell(
                          onTap: () => setState(() {
                            _color = value;
                            _controller.text = _hex(value);
                          }),
                          borderRadius: BorderRadius.circular(24),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Color(value),
                                shape: BoxShape.circle,
                                border: Border.all(color: scheme.outline),
                              ),
                              child: _color == value
                                  ? Icon(
                                      Icons.check,
                                      color:
                                          Color(value).computeLuminance() > 0.5
                                          ? Colors.black
                                          : Colors.white,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                maxLength: 7,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: l10n.topicCardStyle_titleColorCustom,
                  hintText: '#336699',
                  errorText: _color == null
                      ? l10n.topicCardStyle_titleColorInvalid
                      : null,
                ),
                onChanged: (value) => setState(() {
                  final hex = value.trim().replaceFirst(RegExp(r'^#'), '');
                  _color = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)
                      ? 0xFF000000 | int.parse(hex, radix: 16)
                      : null;
                }),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: scheme.surface,
                child: Text(
                  l10n.topicCardStyle_previewTopicTitle,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
              Text(l10n.topicCardStyle_titleColorHint),
              if (_color != null && contrast < 4.5) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.topicCardStyle_titleColorLowContrast,
                  style: TextStyle(color: scheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.common_cancel),
        ),
        FilledButton(
          onPressed: _color == null
              ? null
              : () => Navigator.pop(context, _color),
          child: Text(l10n.common_save),
        ),
      ],
    );
  }
}
