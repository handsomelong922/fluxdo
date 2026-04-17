import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/shortcut_binding.dart';
import '../pages/create_topic_page.dart';
import '../pages/search_page.dart';
import '../providers/topic_list/tab_state_provider.dart';
import '../pages/settings_page.dart';
import '../pages/topics_page.dart';
import '../providers/shortcut_provider.dart';
import '../utils/platform_utils.dart';
import 'notification/notification_quick_panel.dart';
import 'shortcut_help_overlay.dart';

/// 全局键盘快捷键处理器
///
/// 使用 [HardwareKeyboard] 直接监听按键事件，不依赖 Flutter 焦点系统，
/// 确保快捷键在任何交互状态下都能触发。
class KeyboardShortcutHandler extends ConsumerStatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const KeyboardShortcutHandler({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  @override
  ConsumerState<KeyboardShortcutHandler> createState() =>
      _KeyboardShortcutHandlerState();
}

class _KeyboardShortcutHandlerState
    extends ConsumerState<KeyboardShortcutHandler> {
  bool _isHelpOverlayOpen = false;

  @override
  void initState() {
    super.initState();
    if (PlatformUtils.isDesktop) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    }
  }

  @override
  void dispose() {
    if (PlatformUtils.isDesktop) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    }
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    // 如果焦点在文本输入框中，不拦截（让用户正常打字）
    if (_isFocusInTextInput()) return false;

    // 有弹框/底部弹窗等模态路由时，不拦截快捷键
    // （让 Flutter 默认行为处理，如 ESC 关闭弹框）
    // 例外：? 帮助面板的切换关闭由 _handleGlobalAction 处理
    if (_isModalOnTop()) {
      // 只允许帮助面板切换（用于关闭）
      final bindings = ref.read(shortcutProvider);
      for (final binding in bindings) {
        if (binding.action == ShortcutAction.showShortcutHelp &&
            matchKeyEvent(event, binding.activator) &&
            _isHelpOverlayOpen) {
          final navContext = widget.navigatorKey.currentContext;
          if (navContext != null) Navigator.of(navContext).pop();
          _isHelpOverlayOpen = false;
          return true;
        }
      }
      return false;
    }

    final bindings = ref.read(shortcutProvider);

    for (final binding in bindings) {
      if (!matchKeyEvent(event, binding.activator)) continue;

      // 先尝试上下文回调（J/K/Enter 等页面级动作）
      final callback = _resolveContextCallback(binding.action);
      if (callback != null) {
        callback();
        return true;
      }

      // 全局动作
      final handled = _handleGlobalAction(binding.action);
      if (handled) return true;
    }

    return false;
  }

  /// 检查是否有模态路由（Dialog/BottomSheet）在栈顶
  bool _isModalOnTop() {
    final nav = widget.navigatorKey.currentState;
    if (nav == null) return false;
    var isModal = false;
    nav.popUntil((route) {
      if (route.isCurrent && route is ModalRoute && !route.isFirst) {
        // 非首页路由且是当前路由 — 检查是否是 Dialog/BottomSheet 类型
        if (route is DialogRoute || route is ModalBottomSheetRoute) {
          isModal = true;
        }
      }
      return true; // 不实际 pop
    });
    return isModal;
  }

  /// 根据活跃面板解析上下文回调
  VoidCallback? _resolveContextCallback(ShortcutAction action) {
    // 1. 单栏模式的上下文回调（优先级最高，全屏详情页等）
    final singlePane = ref.read(contextShortcutsProvider);
    if (singlePane.containsKey(action)) return singlePane[action];

    // 2. 双栏模式：仅查找活跃面板的回调，不回退到另一面板
    final activePane = ref.read(activePaneProvider);
    final activeCallbacks = activePane == ActivePane.master
        ? ref.read(masterShortcutsProvider)
        : ref.read(detailShortcutsProvider);
    if (activeCallbacks.containsKey(action)) return activeCallbacks[action];

    return null;
  }

  bool _handleGlobalAction(ShortcutAction action) {
    final nav = widget.navigatorKey.currentState;
    if (nav == null) return false;

    switch (action) {
      case ShortcutAction.navigateBack:
      case ShortcutAction.navigateBackAlt:
        nav.maybePop();
        return true;
      case ShortcutAction.openSearch:
        if (_isTopRoute(nav, 'search')) return true;
        nav.push(MaterialPageRoute(
          settings: const RouteSettings(name: 'search'),
          builder: (_) => const SearchPage(),
        ));
        return true;
      case ShortcutAction.openSettings:
        if (_isTopRoute(nav, 'settings')) return true;
        nav.push(MaterialPageRoute(
          settings: const RouteSettings(name: 'settings'),
          builder: (_) => const SettingsPage(),
        ));
        return true;
      case ShortcutAction.refresh:
        final activePane = ref.read(activePaneProvider);
        if (activePane == ActivePane.detail) {
          detailRefreshNotifier.value++;
        } else {
          masterRefreshNotifier.value++;
        }
        desktopRefreshNotifier.value++;
        return true;
      case ShortcutAction.showShortcutHelp:
        // 切换：已打开则关闭，未打开则打开
        final navContext = widget.navigatorKey.currentContext;
        if (navContext == null) return true;
        if (_isHelpOverlayOpen) {
          Navigator.of(navContext).pop();
        } else {
          _isHelpOverlayOpen = true;
          showShortcutHelpOverlay(navContext, ref).then((_) {
            _isHelpOverlayOpen = false;
          });
        }
        return true;
      case ShortcutAction.switchPane:
        final current = ref.read(activePaneProvider);
        ref.read(activePaneProvider.notifier).state =
            current == ActivePane.master
                ? ActivePane.detail
                : ActivePane.master;
        // 触发 HUD 信号（仅键盘切换时）
        ref.read(paneSwitchSignalProvider.notifier).update((v) => v + 1);
        return true;
      case ShortcutAction.toggleNotifications:
        final navContext = widget.navigatorKey.currentContext;
        if (navContext != null) {
          NotificationQuickPanel.show(navContext);
        }
        return true;
      case ShortcutAction.switchToTopics:
        ref.read(switchTabProvider.notifier).state = 0;
        return true;
      case ShortcutAction.switchToProfile:
        ref.read(switchTabProvider.notifier).state = 1;
        return true;
      case ShortcutAction.createTopic:
        if (_isTopRoute(nav, 'search') || _isTopRoute(nav, 'settings')) {
          return true;
        }
        nav.push(MaterialPageRoute(
          builder: (_) => CreateTopicPage(
            initialCategoryId: ref.read(currentTabCategoryIdProvider),
          ),
        ));
        return true;
      // 以下是上下文动作，不在此处处理
      case ShortcutAction.closeOverlay:
      case ShortcutAction.nextItem:
      case ShortcutAction.previousItem:
      case ShortcutAction.openItem:
      case ShortcutAction.toggleAiPanel:
        toggleAiPanelNotifier.value++;
        return true;
      case ShortcutAction.previousTab:
      case ShortcutAction.nextTab:
        return false;
    }
  }

  /// 检查当前栈顶路由名是否匹配
  bool _isTopRoute(NavigatorState nav, String routeName) {
    var isTop = false;
    nav.popUntil((route) {
      if (route.isCurrent) {
        isTop = route.settings.name == routeName;
      }
      return true; // 不实际 pop，只是遍历
    });
    return isTop;
  }

  /// 检查焦点是否在文本输入框中
  bool _isFocusInTextInput() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.context == null) return false;
    var element = focus!.context! as Element;
    var found = false;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is EditableText) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
