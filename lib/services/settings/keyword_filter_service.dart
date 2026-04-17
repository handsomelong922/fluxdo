// CUSTOM: Keyword Filter
// 帖子标题正则关键词屏蔽服务
// - 使用 shared_preferences 持久化正则列表
// - 提供 matches(title) 判断是否命中任一正则
// - 通过 keywordFilterProvider 在 Riverpod 中共享状态

// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/theme_provider.dart'; // sharedPreferencesProvider

// CUSTOM: Keyword Filter
class KeywordFilterNotifier extends StateNotifier<List<String>> {
  static const String _storageKey = 'custom_keyword_filter_patterns';

  final SharedPreferences _prefs;

  KeywordFilterNotifier(this._prefs) : super(_load(_prefs));

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
    _save();
    return true;
  }

  /// 按索引删除
  void removeAt(int index) {
    if (index < 0 || index >= state.length) return;
    final list = [...state]..removeAt(index);
    state = list;
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
    _save();
    return true;
  }

  /// 按值删除
  void remove(String pattern) {
    if (!state.contains(pattern)) return;
    state = state.where((e) => e != pattern).toList();
    _save();
  }

  /// 判断标题是否命中任意一条正则（大小写不敏感）
  bool matches(String? title) {
    if (title == null || title.isEmpty) return false;
    if (state.isEmpty) return false;
    for (final pattern in state) {
      try {
        if (RegExp(pattern, caseSensitive: false).hasMatch(title)) {
          return true;
        }
      } catch (_) {
        // 非法正则（数据损坏场景）直接跳过
      }
    }
    return false;
  }

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
}

// CUSTOM: Keyword Filter
final keywordFilterProvider =
    StateNotifierProvider<KeywordFilterNotifier, List<String>>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return KeywordFilterNotifier(prefs);
});
