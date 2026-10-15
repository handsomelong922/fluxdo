import 'dart:collection';

/// 字面关键词前缀索引。保持输入顺序归因，不改变大小写或完整词语义。
/// 用户正则不进入此索引，仍由可取消的隔离区执行。
class TopicKeywordMatcher {
  TopicKeywordMatcher(List<String> keywords, this.wholeWord)
    : keywords = List.unmodifiable(keywords) {
    for (var i = 0; i < keywords.length; i++) {
      final keyword = keywords[i];
      if (keyword.isEmpty) continue;
      var node = _root;
      for (final code in keyword.codeUnits) {
        node = node.children.putIfAbsent(code, _KeywordNode.new);
      }
      // 重复规则仍以第一条为准。
      node.rule ??= i;
      node.needsBoundary = wholeWord && keyword.codeUnits.every(_isWordCode);
    }
  }

  final List<String> keywords;
  final bool wholeWord;
  final _root = _KeywordNode();
  final _cache = LinkedHashMap<String, String?>();
  int _cachedUnits = 0;
  static const _maxCachedTitles = 2048;
  static const _maxCachedUnits = 262144;

  /// 比较内容而非列表身份，兼容调用者原地修改规则；无关设置重建不会失效。
  bool hasRules(List<String> other, bool wholeWord) {
    if (this.wholeWord != wholeWord || keywords.length != other.length) {
      return false;
    }
    for (var i = 0; i < other.length; i++) {
      if (keywords[i] != other[i]) return false;
    }
    return true;
  }

  String? match(String title) {
    if (keywords.isEmpty) return null;
    if (_cache.containsKey(title)) {
      final result = _cache.remove(title);
      _cache[title] = result;
      return result;
    }
    final result = _match(title);
    // 同时限制条目数与 UTF-16 总长度，超长标题仍完整匹配但不常驻缓存。
    if (title.length <= _maxCachedUnits) {
      while (_cache.isNotEmpty &&
          (_cache.length >= _maxCachedTitles ||
              _cachedUnits + title.length > _maxCachedUnits)) {
        final oldest = _cache.keys.first;
        _cachedUnits -= oldest.length;
        _cache.remove(oldest);
      }
      _cache[title] = result;
      _cachedUnits += title.length;
    }
    return result;
  }

  String? _match(String title) {
    if (keywords.isEmpty) return null;
    final lower = title.toLowerCase();
    int? firstRule;
    var steps = 0;
    final maxSteps = lower.length * 16 + 1024;
    for (var start = 0; start < lower.length; start++) {
      var node = _root;
      for (var end = start; end < lower.length; end++) {
        // 极长共同前缀可能反复扫描同一后缀，退回原生 indexOf，
        // 不截断规则或标题，也不让前缀索引引入无界平方级退化。
        if (++steps > maxSteps) return _matchLinearly(lower);
        final next = node.children[lower.codeUnitAt(end)];
        if (next == null) break;
        node = next;
        final rule = node.rule;
        if (rule == null || (firstRule != null && rule >= firstRule)) continue;
        if (node.needsBoundary &&
            ((start > 0 && _isWordCode(lower.codeUnitAt(start - 1))) ||
                (end + 1 < lower.length &&
                    _isWordCode(lower.codeUnitAt(end + 1))))) {
          continue;
        }
        // 返回规则顺序最早的命中，而不是标题中位置最早的命中。
        if (rule == 0) return keywords[0];
        firstRule = rule;
      }
    }
    return firstRule == null ? null : keywords[firstRule];
  }

  String? _matchLinearly(String lower) {
    for (final keyword in keywords) {
      if (keyword.isEmpty) continue;
      final boundary = wholeWord && keyword.codeUnits.every(_isWordCode);
      var index = lower.indexOf(keyword);
      while (index >= 0) {
        final end = index + keyword.length;
        if (!boundary ||
            ((index == 0 || !_isWordCode(lower.codeUnitAt(index - 1))) &&
                (end == lower.length || !_isWordCode(lower.codeUnitAt(end))))) {
          return keyword;
        }
        index = lower.indexOf(keyword, index + 1);
      }
    }
    return null;
  }

  static bool _isWordCode(int code) =>
      (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A) ||
      code == 0x5F;
}

class _KeywordNode {
  final children = <int, _KeywordNode>{};
  int? rule;
  bool needsBoundary = false;
}
