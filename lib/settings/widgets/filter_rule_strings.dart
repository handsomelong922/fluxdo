import 'package:flutter/widgets.dart';

/// 分支功能的独立文案，避免与上游生成的 ARB 文件冲突。
class FilterRuleStrings {
  final bool chinese;
  FilterRuleStrings(BuildContext context)
    : chinese = Localizations.localeOf(context).languageCode == 'zh';

  String get regex =>
      chinese ? '正则表达式（后台匹配）' : 'Regular expression (background matching)';
  String get literal => chinese ? '关键词（字面匹配）' : 'Keyword (literal match)';
  String get add => chinese ? '添加规则' : 'Add rule';
  String get update => chinese ? '更新规则' : 'Update rule';
  String get clear => chinese ? '清空规则' : 'Clear rules';
  String get hint => chinese
      ? '输入规则，或点击已有规则编辑'
      : 'Enter a rule, or tap an existing rule to edit';
  String get help => chinese
      ? r'支持 Dart RegExp 语法，包括环视、反向引用和命名分组，例如 (?=.*手机)(?=.*求助)。不是 PCRE；不支持的语法会在保存前提示。正则不区分大小写，不受完整词开关影响，其他模式使用 Dart 默认值。每条最多 65536 字符，最多 32 条，总计 262144 字符。规则保留原文，不拆分；后台匹配超过 2 秒会终止并提示，未验证标题保持隐藏。'
      : r'Supports Dart RegExp, including lookaround, backreferences and named groups, e.g. (?=.*phone)(?=.*help). This is not PCRE; unsupported syntax is reported before saving. Case-insensitive, independent of whole-word mode; other flags use Dart defaults. Up to 65536 characters per rule, 32 rules and 262144 characters total. Rules are preserved without splitting. Background matching stops after 2 seconds; unchecked titles remain hidden with an error.';
  String get usernameHelp => chinese
      ? '支持空格、换行、英文或中文逗号分隔；自动移除 @ 并去重'
      : 'Separate with whitespace or English/Chinese commas; @ prefixes and duplicates are removed';

  String error(FormatException error) => switch (error.message) {
    'length' =>
      chinese
          ? '规则不能为空，且最多 65536 个字符。'
          : 'Enter a rule of at most 65536 characters.',
    'count' =>
      chinese ? '最多保存 32 条正则规则。' : 'You can save up to 32 regex rules.',
    'total' =>
      chinese
          ? '正则规则总长度不能超过 262144 字符。'
          : 'Total regex length cannot exceed 262144 characters.',
    'timeout' => chinese ? '正则处理超时，请简化规则后重试。草稿已保留。' : 'Regex processing timed out. Simplify the rule and retry. Your draft is preserved.',
    'worker' =>
      chinese
          ? '后台正则验证失败，请重试。草稿已保留。'
          : 'Background validation failed. Retry; your draft is preserved.',
    _ =>
      chinese
          ? '正则表达式无效：${error.source ?? "请检查 Dart 正则语法"}'
          : 'Invalid regular expression: ${error.source ?? "check Dart regex syntax"}',
  };
}
