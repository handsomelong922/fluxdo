// CUSTOM: Keyword Filter
// 帖子标题正则关键词屏蔽服务
// - 使用 shared_preferences 持久化正则列表
// - 提供 matches(title) 判断是否命中任一正则
// - 通过 keywordFilterProvider 在 Riverpod 中共享状态

// ignore: depend_on_referenced_packages
import 'dart:collection';

import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/theme_provider.dart'; // sharedPreferencesProvider

// CUSTOM: Keyword Filter
class KeywordFilterNotifier extends StateNotifier<List<String>> {
  static const String _storageKey = 'custom_keyword_filter_patterns';
  static const int _maxMatchCacheEntries = 512;

  final SharedPreferences _prefs;
  List<RegExp> _compiledPatterns = const <RegExp>[];
  final LinkedHashMap<String, bool> _matchCache = LinkedHashMap<String, bool>();

  KeywordFilterNotifier(this._prefs) : super(_load(_prefs)) {
    _rebuildCompiledPatterns();
  }

  static List<String> _load(SharedPreferences prefs) {
    return prefs.getStringList(_storageKey) ?? const <String>[];
  }

  /// 添加一条正则；无效或重复则忽略
  /// 返回是否添加成功
  bool add(String pattern) {
    final trimmed = pattern.trim();
    if (trimmed.isEmpty) return false;
    if (state.contains(trimmed)) return false;
    if (!isValidRegex(trimmed)) return false;
    state = [...state, trimmed];
    _rebuildCompiledPatterns();
    _save();
    return true;
  }

  /// 按索引删除
  void removeAt(int index) {
    if (index < 0 || index >= state.length) return;
    final list = [...state]..removeAt(index);
    state = list;
    _rebuildCompiledPatterns();
    _save();
  }

  /// CUSTOM: Keyword Filter 编辑指定位置的正则
  /// 返回是否编辑成功（空、非法正则、与其它条目重复均会拒绝）
  bool editAt(int index, String newRegex) {
    if (index < 0 || index >= state.length) return false;
    final trimmed = newRegex.trim();
    if (trimmed.isEmpty) return false;
    if (!isValidRegex(trimmed)) return false;
    // 同位置未变更视为成功空操作
    if (state[index] == trimmed) return true;
    // 避免与其它条目重复
    for (var i = 0; i < state.length; i++) {
      if (i != index && state[i] == trimmed) return false;
    }
    final list = [...state];
    list[index] = trimmed;
    state = list;
    _rebuildCompiledPatterns();
    _save();
    return true;
  }

  /// 批量替换所有规则。
  /// 返回是否保存成功（空、非法正则、重复项均会拒绝）。
  bool replaceAllPatterns(List<String> patterns) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final pattern in patterns) {
      final trimmed = pattern.trim();
      if (trimmed.isEmpty || !isValidRegex(trimmed)) return false;
      if (!seen.add(trimmed)) return false;
      normalized.add(trimmed);
    }
    state = normalized;
    _rebuildCompiledPatterns();
    _save();
    return true;
  }

  /// 按值删除
  void remove(String pattern) {
    if (!state.contains(pattern)) return;
    state = state.where((e) => e != pattern).toList();
    _rebuildCompiledPatterns();
    _save();
  }

  /// 判断标题是否命中任意一条正则（大小写不敏感）
  bool matches(String? title) {
    if (title == null || title.isEmpty) return false;
    if (_compiledPatterns.isEmpty) return false;
    if (_matchCache.containsKey(title)) {
      final cached = _matchCache.remove(title)!;
      _matchCache[title] = cached;
      return cached;
    }

    for (final pattern in _compiledPatterns) {
      if (pattern.hasMatch(title)) {
        _cacheMatchResult(title, true);
        return true;
      }
    }
    _cacheMatchResult(title, false);
    return false;
  }

  @visibleForTesting
  int get debugMatchCacheSize => _matchCache.length;

  static bool isValidRegex(String pattern) {
    try {
      RegExp(pattern);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _save() {
    _prefs.setStringList(_storageKey, state);
  }

  void _rebuildCompiledPatterns() {
    final compiled = <RegExp>[];
    for (final pattern in state) {
      try {
        compiled.add(RegExp(pattern, caseSensitive: false));
      } catch (_) {
        // 非法正则（数据损坏场景）直接跳过。
      }
    }
    _compiledPatterns = compiled;
    _matchCache.clear();
  }

  void _cacheMatchResult(String title, bool matched) {
    if (_matchCache.length >= _maxMatchCacheEntries) {
      _matchCache.remove(_matchCache.keys.first);
    }
    _matchCache[title] = matched;
  }
}

// CUSTOM: Keyword Filter
final keywordFilterProvider =
    StateNotifierProvider<KeywordFilterNotifier, List<String>>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider);
      return KeywordFilterNotifier(prefs);
    });
