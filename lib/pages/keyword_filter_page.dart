// CUSTOM: Keyword Filter
// 关键词屏蔽（正则）设置页 - 极简实现
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings/keyword_filter_service.dart';

// CUSTOM: Keyword Filter
class KeywordFilterPage extends ConsumerStatefulWidget {
  const KeywordFilterPage({super.key});

  @override
  ConsumerState<KeywordFilterPage> createState() => _KeywordFilterPageState();
}

class _KeywordFilterPageState extends ConsumerState<KeywordFilterPage> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addPattern() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _errorText = '不能为空');
      return;
    }
    if (!KeywordFilterNotifier.isValidRegex(text)) {
      setState(() => _errorText = '无效的正则表达式');
      return;
    }
    final notifier = ref.read(keywordFilterProvider.notifier);
    final ok = notifier.add(text);
    if (!ok) {
      setState(() => _errorText = '已存在相同规则');
      return;
    }
    _controller.clear();
    setState(() => _errorText = null);
  }

  // CUSTOM: Keyword Filter 弹出对话框编辑指定正则
  Future<void> _editPattern(int index, String oldPattern) async {
    final editController = TextEditingController(text: oldPattern);
    String? dialogError;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          String? validate(String text) {
            final t = text.trim();
            if (t.isEmpty) return '不能为空';
            if (!KeywordFilterNotifier.isValidRegex(t)) return '无效的正则表达式';
            return null;
          }

          void onSave() {
            final t = editController.text.trim();
            final err = validate(t);
            if (err != null) {
              setDialogState(() => dialogError = err);
              return;
            }
            final ok = ref
                .read(keywordFilterProvider.notifier)
                .editAt(index, t);
            if (!ok) {
              setDialogState(() => dialogError = '与其它规则重复或保存失败');
              return;
            }
            Navigator.of(ctx).pop(true);
          }

          return AlertDialog(
            title: const Text('编辑屏蔽规则'),
            content: TextField(
              controller: editController,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (dialogError != null) {
                  setDialogState(() => dialogError = null);
                }
              },
              onSubmitted: (_) => onSave(),
              decoration: InputDecoration(
                hintText: '输入新的正则表达式',
                errorText: dialogError,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: onSave,
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    editController.dispose();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('规则已更新'),
          duration: Duration(seconds: 1),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final patterns = ref.watch(keywordFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('关键词屏蔽'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: '输入正则表达式，例如 广告|推广',
                      errorText: _errorText,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addPattern(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _addPattern,
                  child: const Text('添加'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '命中标题的帖子将不会显示在列表中（大小写不敏感）',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: patterns.isEmpty
                ? Center(
                    child: Text(
                      '尚未添加屏蔽规则',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: patterns.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final pattern = patterns[index];
                      return ListTile(
                        title: Text(
                          pattern,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        // CUSTOM: Keyword Filter 编辑 + 删除
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              tooltip: '编辑',
                              onPressed: () => _editPattern(index, pattern),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: '删除',
                              onPressed: () => ref
                                  .read(keywordFilterProvider.notifier)
                                  .removeAt(index),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
