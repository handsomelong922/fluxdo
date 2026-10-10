import 'package:flutter/widgets.dart';

/// 分支功能的独立文案，避免与上游生成的 ARB 文件冲突。
class FilterRuleStrings {
  final bool chinese;
  FilterRuleStrings(BuildContext context)
      : chinese = Localizations.localeOf(context).languageCode == 'zh';

  String get regex => chinese ? '正则表达式（安全子集）' : 'Regular expression (safe subset)';
  String get literal => chinese ? '关键词（字面匹配）' : 'Keyword (literal match)';
  String get add => chinese ? '添加规则' : 'Add rule';
  String get update => chinese ? '更新规则' : 'Update rule';
  String get clear => chinese ? '清空规则' : 'Clear rules';
  String get hint => chinese ? '输入规则，或点击已有规则编辑' : 'Enter a rule, or tap an existing rule to edit';
  String get help => chinese
      ? r'支持分组、|、字符类、锚点和重复，例如 (求助|提问).*(手机|电脑)。不支持环视、反向引用、命名分组和 Unicode 属性。正则不区分大小写，不受完整词开关影响。最多 32 条、每条 2048 字符、有界重复最多 64 次，单条最多 512 状态、总计 2048 状态；超过 4096 字符的异常标题不做正则过滤。'
      : r'Supports groups, |, character classes, anchors and repetition, e.g. (help|question).*(phone|computer). Lookaround, backreferences, named groups and Unicode properties are unsupported. Regex is case-insensitive and independent of whole-word mode. Up to 32 rules, 2048 characters per rule, bounded repetition up to 64, up to 512 compiled states per rule and 2048 in total. Titles longer than 4096 characters are excluded from regex filtering.';
  String get usernameHelp => chinese
      ? '支持空格、换行、英文或中文逗号分隔；自动移除 @ 并去重'
      : 'Separate with whitespace or English/Chinese commas; @ prefixes and duplicates are removed';

  String error(FormatException error) => switch (error.message) {
    'unsupported' => chinese ? '不支持此正则语法：请去除环视、反向引用、命名分组或不支持的转义。' : 'Unsupported syntax: remove lookaround, backreferences, named groups or unsupported escapes.',
    'length' => chinese ? '规则不能为空，且最多 2048 个字符。' : 'Enter a rule of at most 2048 characters.',
    'count' => chinese ? '最多保存 32 条正则规则。' : 'You can save up to 32 regex rules.',
    'repeat' => chinese ? '有界重复次数不能超过 64。' : 'Bounded repetition cannot exceed 64.',
    'complexity' => chinese ? '规则过于复杂，请缩短表达式或减少重复与分支。' : 'Rule is too complex. Reduce its length, repetition or alternatives.',
    _ => chinese ? '正则表达式无效，请检查括号、字符类及量词。' : 'Invalid regular expression. Check groups, character classes and quantifiers.',
  };
}
