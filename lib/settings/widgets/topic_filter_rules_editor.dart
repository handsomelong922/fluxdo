import 'package:flutter/material.dart';

import '../../utils/topic_regex_rules.dart';
import 'filter_rule_strings.dart';

/// 字面关键词和显式正则共用编辑器，编辑只更新本地草稿，确认后才持久化。
class TopicFilterRulesEditor extends StatefulWidget {
  final List<String> initialKeywords;
  final List<String> initialRegexPatterns;

  const TopicFilterRulesEditor({
    super.key,
    required this.initialKeywords,
    required this.initialRegexPatterns,
  });

  @override
  State<TopicFilterRulesEditor> createState() => TopicFilterRulesEditorState();
}

typedef TopicFilterRules = ({
  List<String> keywords,
  List<String> regexPatterns,
});

class TopicFilterRulesEditorState extends State<TopicFilterRulesEditor> {
  final _controller = TextEditingController();
  late final List<(String, bool)> _rules;
  int? _editing;
  bool _regex = false;
  bool _busy = false;
  FormatException? _error;

  @override
  void initState() {
    super.initState();
    _rules = [
      for (final keyword in widget.initialKeywords) (keyword, false),
      for (final pattern in widget.initialRegexPatterns) (pattern, true),
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 连同尚未点「添加」的输入一起验证；失败时保留全部草稿和原有规则。
  Future<TopicFilterRules?> collectRules() async {
    if (!await _commitInput() || !mounted) return null;
    final result = (
      keywords: _rules
          .where((rule) => !rule.$2)
          .map((rule) => rule.$1)
          .toList(),
      regexPatterns: _rules
          .where((rule) => rule.$2)
          .map((rule) => rule.$1)
          .toList(),
    );
    setState(() => _busy = true);
    try {
      await TopicRegexRules.validate(result.regexPatterns);
      if (!mounted) return null;
      return result;
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _commitInput() async {
    if (_busy) return false;
    final value = _regex ? _controller.text : _controller.text.trim();
    if (value.isEmpty && _editing == null) return true;
    setState(() => _busy = true);
    final next = List<(String, bool)>.from(_rules);
    final replacements = _regex || _editing != null
        ? [value]
        : value
              .split(RegExp(r'[\r\n]+'))
              .map((part) => part.trim())
              .where((part) => part.isNotEmpty)
              .toList();
    try {
      if (value.isEmpty) throw const FormatException('length');
      if (_editing != null) next.removeAt(_editing!);
      var insertAt = _editing ?? next.length;
      for (final pattern in replacements) {
        final rule = (pattern, _regex);
        if (!next.contains(rule)) next.insert(insertAt++, rule);
      }
      await TopicRegexRules.validate(
        next.where((rule) => rule.$2).map((rule) => rule.$1).toList(),
      );
    } on FormatException catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _busy = false;
        });
      }
      return false;
    }
    if (!mounted) return false;
    setState(() {
      _busy = false;
      _rules
        ..clear()
        ..addAll(next);
      _controller.clear();
      _editing = null;
      _error = null;
    });
    return true;
  }

  Future<void> _edit(int index) async {
    if (_editing == index) return;
    final selected = _rules[index];
    if (!await _commitInput() || !mounted) return;
    setState(() {
      _editing = _rules.indexOf(selected);
      _regex = selected.$2;
      _controller.text = selected.$1;
      _controller.selection = TextSelection.collapsed(
        offset: selected.$1.length,
      );
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = FilterRuleStrings(context);
    return AbsorbPointer(
      absorbing: _busy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() {
                _rules.clear();
                _controller.clear();
                _editing = null;
                _error = null;
              }),
              child: Text(strings.clear),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var index = 0; index < _rules.length; index++)
                Tooltip(
                  message: _rules[index].$1,
                  child: InputChip(
                    selected: _editing == index,
                    avatar: _rules[index].$2 ? const Text('.*') : null,
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 290),
                      child: Text(
                        _rules[index].$1,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    onPressed: () => _edit(index),
                    onDeleted: () => setState(() {
                      _rules.removeAt(index);
                      if (_editing == index) {
                        _editing = null;
                        _controller.clear();
                        _error = null;
                      } else if (_editing != null && _editing! > index) {
                        _editing = _editing! - 1;
                      }
                    }),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(strings.regex),
            value: _regex,
            onChanged: (value) => setState(() {
              _regex = value;
              _error = null;
            }),
          ),
          TextField(
            key: const ValueKey('topic-filter-rule-input'),
            controller: _controller,
            minLines: 2,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              labelText: _regex ? strings.regex : strings.literal,
              hintText: strings.hint,
              border: const OutlineInputBorder(),
              errorText: _error == null ? null : strings.error(_error!),
              errorMaxLines: 4,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _commitInput,
              child: Text(_editing == null ? strings.add : strings.update),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_regex)
            Text(strings.help, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
