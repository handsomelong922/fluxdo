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
  final List<TextEditingController> _editControllers = [];
  List<String?> _editErrors = const [];
  bool _isEditing = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    _disposeEditControllers();
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

  void _enterEditMode() {
    final patterns = ref.read(keywordFilterProvider);
    _disposeEditControllers();
    _editControllers
      ..clear()
      ..addAll(patterns.map((pattern) => TextEditingController(text: pattern)));
    setState(() {
      _editErrors = List<String?>.filled(_editControllers.length, null);
      _isEditing = true;
      _errorText = null;
    });
  }

  void _cancelEditMode() {
    _disposeEditControllers();
    setState(() {
      _editControllers.clear();
      _editErrors = const [];
      _isEditing = false;
    });
  }

  void _removeEditingPattern(int index) {
    if (index < 0 || index >= _editControllers.length) return;
    final controller = _editControllers.removeAt(index);
    controller.dispose();
    final errors = [..._editErrors]..removeAt(index);
    setState(() => _editErrors = errors);
  }

  void _saveEditingPatterns() {
    final values = _editControllers.map((c) => c.text.trim()).toList();
    final errors = List<String?>.filled(values.length, null);
    final seen = <String, int>{};

    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value.isEmpty) {
        errors[i] = '不能为空';
      } else if (!KeywordFilterNotifier.isValidRegex(value)) {
        errors[i] = '无效的正则表达式';
      } else if (seen.containsKey(value)) {
        errors[i] = '与第 ${seen[value]! + 1} 条重复';
      } else {
        seen[value] = i;
      }
    }

    if (errors.any((error) => error != null)) {
      setState(() => _editErrors = errors);
      return;
    }

    final ok = ref
        .read(keywordFilterProvider.notifier)
        .replaceAllPatterns(values);
    if (!ok) {
      setState(() {
        _editErrors = List<String?>.filled(values.length, '与其它规则重复或保存失败');
      });
      return;
    }

    _disposeEditControllers();
    setState(() {
      _editControllers.clear();
      _editErrors = const [];
      _isEditing = false;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('规则已保存'), duration: Duration(seconds: 1)),
      );
  }

  void _disposeEditControllers() {
    for (final controller in _editControllers) {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final patterns = ref.watch(keywordFilterProvider);
    final canEdit = patterns.isNotEmpty;
    final itemCount = _isEditing ? _editControllers.length : patterns.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('关键词屏蔽'),
        actions: [
          if (_isEditing) ...[
            TextButton.icon(
              onPressed: _saveEditingPatterns,
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存'),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '取消编辑',
              onPressed: _cancelEditMode,
            ),
          ],
        ],
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
                    enabled: !_isEditing,
                    decoration: InputDecoration(
                      hintText: _isEditing ? '编辑中请先保存或取消' : '输入正则表达式，例如 广告|推广',
                      errorText: _errorText,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: _isEditing ? null : (_) => _addPattern(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isEditing ? null : _addPattern,
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
            child: itemCount == 0
                ? Center(
                    child: Text(
                      '尚未添加屏蔽规则',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: itemCount,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final pattern = _isEditing
                          ? _editControllers[index].text
                          : patterns[index];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (!_isEditing)
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    tooltip: '编辑',
                                    onPressed: canEdit ? _enterEditMode : null,
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: '删除',
                                  onPressed: _isEditing
                                      ? () => _removeEditingPattern(index)
                                      : () => ref
                                            .read(
                                              keywordFilterProvider.notifier,
                                            )
                                            .removeAt(index),
                                ),
                              ],
                            ),
                            if (_isEditing)
                              TextField(
                                controller: _editControllers[index],
                                minLines: 1,
                                maxLines: 3,
                                decoration: InputDecoration(
                                  labelText: '规则 ${index + 1}',
                                  errorText: index < _editErrors.length
                                      ? _editErrors[index]
                                      : null,
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                style: const TextStyle(fontFamily: 'monospace'),
                                onChanged: (_) {
                                  if (index < _editErrors.length &&
                                      _editErrors[index] != null) {
                                    final errors = [..._editErrors];
                                    errors[index] = null;
                                    setState(() => _editErrors = errors);
                                  }
                                },
                              )
                            else
                              SelectableText(
                                pattern,
                                style: const TextStyle(fontFamily: 'monospace'),
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
