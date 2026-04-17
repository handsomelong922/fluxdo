import 'dart:convert';

// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shortcut_binding.dart';
import 'theme_provider.dart'; // sharedPreferencesProvider

/// 快捷键状态管理
class ShortcutNotifier extends StateNotifier<List<ShortcutBinding>> {
  static const _prefsKey = 'shortcuts_custom';

  ShortcutNotifier(this._prefs) : super(buildDefaultBindings()) {
    _loadCustomBindings();
  }

  final SharedPreferences _prefs;

  /// 从 SharedPreferences 加载用户自定义绑定
  void _loadCustomBindings() {
    final jsonStr = _prefs.getString(_prefsKey);
    if (jsonStr == null) return;

    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      state = state.map((binding) {
        final data = map[binding.action.name] as Map<String, dynamic>?;
        final custom = ShortcutBinding.activatorFromJson(data);
        if (custom != null) {
          return binding.copyWith(customActivator: custom);
        }
        return binding;
      }).toList();
    } catch (_) {
      // JSON 损坏，忽略
    }
  }

  /// 持久化所有自定义绑定
  Future<void> _saveCustomBindings() async {
    final map = <String, dynamic>{};
    for (final binding in state) {
      if (binding.isCustomized) {
        map[binding.action.name] =
            ShortcutBinding.activatorToJson(binding.customActivator!);
      }
    }
    if (map.isEmpty) {
      await _prefs.remove(_prefsKey);
    } else {
      await _prefs.setString(_prefsKey, jsonEncode(map));
    }
  }

  /// 更新某个动作的快捷键绑定
  Future<void> updateBinding(
      ShortcutAction action, SingleActivator activator) async {
    state = state.map((b) {
      if (b.action == action) {
        return b.copyWith(customActivator: activator);
      }
      return b;
    }).toList();
    await _saveCustomBindings();
  }

  /// 重置单个动作为默认
  Future<void> resetBinding(ShortcutAction action) async {
    state = state.map((b) {
      if (b.action == action) {
        return b.copyWith(clearCustom: true);
      }
      return b;
    }).toList();
    await _saveCustomBindings();
  }

  /// 重置全部为默认
  Future<void> resetAll() async {
    state = buildDefaultBindings();
    await _prefs.remove(_prefsKey);
  }

  /// 查找与指定激活器冲突的动作，排除 excludeAction
  ShortcutAction? findConflict(
    SingleActivator activator, {
    ShortcutAction? excludeAction,
  }) {
    for (final binding in state) {
      if (binding.action == excludeAction) continue;
      if (_activatorsEqual(binding.activator, activator)) {
        return binding.action;
      }
    }
    return null;
  }

  /// 获取指定动作的绑定
  ShortcutBinding? getBinding(ShortcutAction action) {
    for (final binding in state) {
      if (binding.action == action) return binding;
    }
    return null;
  }

  /// 构建用于 CallbackShortcuts 的 bindings map
  Map<ShortcutActivator, VoidCallback> buildBindingsMap(
    Map<ShortcutAction, VoidCallback> callbacks,
  ) {
    final result = <ShortcutActivator, VoidCallback>{};
    for (final binding in state) {
      final callback = callbacks[binding.action];
      if (callback != null) {
        result[binding.activator] = callback;
      }
    }
    return result;
  }

  static bool _activatorsEqual(SingleActivator a, SingleActivator b) {
    return a.trigger == b.trigger &&
        a.control == b.control &&
        a.shift == b.shift &&
        a.alt == b.alt &&
        a.meta == b.meta;
  }
}

final shortcutProvider =
    StateNotifierProvider<ShortcutNotifier, List<ShortcutBinding>>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ShortcutNotifier(prefs);
});

/// 双栏活跃面板
enum ActivePane { master, detail }

/// 当前活跃面板（决定 J/K 控制哪一侧）
final activePaneProvider = StateProvider<ActivePane>((ref) => ActivePane.master);

/// 主面板（话题列表）的上下文快捷键
final masterShortcutsProvider =
    StateProvider<Map<ShortcutAction, VoidCallback>>((ref) => {});

/// 详情面板（帖子详情）的上下文快捷键
final detailShortcutsProvider =
    StateProvider<Map<ShortcutAction, VoidCallback>>((ref) => {});

/// 单栏模式的上下文快捷键（兼容非双栏场景）
final contextShortcutsProvider =
    StateProvider<Map<ShortcutAction, VoidCallback>>((ref) => {});

/// 桌面端刷新信号（ValueNotifier，不依赖 Riverpod）
/// 页面在 initState/dispose 中 addListener/removeListener
final desktopRefreshNotifier = ValueNotifier<int>(0);

/// 桌面端主面板刷新信号
final masterRefreshNotifier = ValueNotifier<int>(0);

/// 桌面端详情面板刷新信号
final detailRefreshNotifier = ValueNotifier<int>(0);

/// 外部切换首页 tab 的信号（-1 表示无操作）
final switchTabProvider = StateProvider<int>((ref) => -1);

/// AI 面板切换信号
final toggleAiPanelNotifier = ValueNotifier<int>(0);

/// 键盘触发的面板切换信号（自增计数，HUD 监听变化来显示）
final paneSwitchSignalProvider = StateProvider<int>((ref) => 0);

/// Shift 组合键映射表：基础键 → Shift 后的键
final _shiftKeyMap = <LogicalKeyboardKey, LogicalKeyboardKey>{
  LogicalKeyboardKey.slash: LogicalKeyboardKey.question,
  LogicalKeyboardKey.digit1: LogicalKeyboardKey.exclamation,
  LogicalKeyboardKey.digit2: LogicalKeyboardKey.at,
  LogicalKeyboardKey.semicolon: LogicalKeyboardKey.colon,
  LogicalKeyboardKey.equal: LogicalKeyboardKey.add,
  LogicalKeyboardKey.minus: LogicalKeyboardKey.underscore,
  LogicalKeyboardKey.bracketLeft: LogicalKeyboardKey.braceLeft,
  LogicalKeyboardKey.bracketRight: LogicalKeyboardKey.braceRight,
  LogicalKeyboardKey.backslash: LogicalKeyboardKey.bar,
  LogicalKeyboardKey.quote: LogicalKeyboardKey.quoteSingle,
  LogicalKeyboardKey.comma: LogicalKeyboardKey.less,
  LogicalKeyboardKey.period: LogicalKeyboardKey.greater,
  LogicalKeyboardKey.backquote: LogicalKeyboardKey.tilde,
};

/// 基础键 → Shift 后的字符（用于 character 级别匹配）
const _shiftCharMap = <String, String>{
  '/': '?',
  '1': '!',
  '2': '@',
  '3': '#',
  ';': ':',
  '=': '+',
  '-': '_',
  '[': '{',
  ']': '}',
  '\\': '|',
  ',': '<',
  '.': '>',
  '`': '~',
};

/// 将 KeyEvent 与 SingleActivator 进行匹配
bool matchKeyEvent(KeyEvent event, SingleActivator activator) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

  final eventKey = event.logicalKey;
  final triggerKey = activator.trigger;
  final keyboard = HardwareKeyboard.instance;

  // 非 shift 修饰键必须严格匹配
  if (activator.control != keyboard.isControlPressed) return false;
  if (activator.alt != keyboard.isAltPressed) return false;
  if (activator.meta != keyboard.isMetaPressed) return false;

  // 情况 1：逻辑键直接匹配 → shift 也必须严格匹配
  if (eventKey == triggerKey) {
    return activator.shift == keyboard.isShiftPressed;
  }

  // 情况 2：Shift 变体——通过 LogicalKeyboardKey 映射匹配（仅 binding 要求 shift）
  if (activator.shift) {
    if (_shiftKeyMap[triggerKey] == eventKey) return true;
    if (_shiftKeyMap[eventKey] == triggerKey && keyboard.isShiftPressed) {
      return true;
    }
  }

  // 情况 3：最终兜底——用事件的实际字符匹配
  // 解决各平台对 Shift+键 报告的 logicalKey 不一致的问题
  if (event is KeyDownEvent && event.character != null) {
    final char = event.character!;
    final triggerLabel = triggerKey.keyLabel;

    if (activator.shift) {
      // binding 要求 shift：检查字符是否是 trigger 的 shifted 版本
      final shiftedChar = _shiftCharMap[triggerLabel.toLowerCase()];
      if (shiftedChar != null && shiftedChar == char) return true;
    } else {
      // binding 不要求 shift：字符必须精确匹配且 shift 未按下
      if (triggerLabel.toLowerCase() == char.toLowerCase() &&
          !keyboard.isShiftPressed) {
        return true;
      }
    }
  }

  return false;
}

