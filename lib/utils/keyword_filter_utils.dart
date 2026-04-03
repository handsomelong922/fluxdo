import 'package:html/parser.dart' as html_parser;

/// 关键词过滤工具
class KeywordFilterUtils {
  const KeywordFilterUtils._();

  /// 解析用户输入：按英文逗号分隔，去空白，忽略空项
  static List<String> parseKeywords(String input) {
    return input
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  /// 任一关键词命中（大小写不敏感）
  static bool containsAnyKeyword({
    required String text,
    required List<String> keywords,
  }) {
    if (text.isEmpty || keywords.isEmpty) return false;
    final lowerText = text.toLowerCase();
    for (final keyword in keywords) {
      if (keyword.isEmpty) continue;
      if (lowerText.contains(keyword.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  /// 从 cooked HTML 提取可见纯文本（用于回复过滤）
  static String htmlToVisibleText(String html) {
    if (html.isEmpty) return '';
    try {
      final fragment = html_parser.parseFragment(html);
      return fragment.text.trim();
    } catch (_) {
      return html;
    }
  }
}
