import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 懒加载作用域
///
/// 在页面级别提供缓存，页面销毁时缓存自动清理
class LazyLoadScope extends StatefulWidget {
  static final int maxCacheEntries =
      defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS
      ? 192
      : 512;

  final Widget child;

  const LazyLoadScope({super.key, required this.child});

  /// 获取当前作用域的缓存
  static _LazyLoadCache? _of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_LazyLoadScopeData>()
        ?.cache;
  }

  /// 检查 key 是否已加载（如果没有作用域则返回 false）
  static bool isLoaded(BuildContext context, String key) {
    return _of(context)?.contains(key) ?? false;
  }

  /// 标记 key 已加载
  static void markLoaded(BuildContext context, String key) {
    _of(context)?.add(key);
  }

  @override
  State<LazyLoadScope> createState() => _LazyLoadScopeState();
}

class _LazyLoadScopeState extends State<LazyLoadScope> {
  final _LazyLoadCache _cache = _LazyLoadCache(
    maxEntries: LazyLoadScope.maxCacheEntries,
  );

  @override
  Widget build(BuildContext context) {
    return _LazyLoadScopeData(cache: _cache, child: widget.child);
  }
}

class _LazyLoadScopeData extends InheritedWidget {
  final _LazyLoadCache cache;

  const _LazyLoadScopeData({required this.cache, required super.child});

  @override
  bool updateShouldNotify(_LazyLoadScopeData oldWidget) => false;
}

/// 懒加载暂停作用域
///
/// 用于在高速滚动期间临时阻止图片/重资源组件触发首次加载，
/// 等滚动停稳后再统一恢复，减少滚动中的 decode/raster 抖动。
class LazyLoadPauseScope extends InheritedNotifier<ValueListenable<bool>> {
  const LazyLoadPauseScope({
    super.key,
    required ValueListenable<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  static ValueListenable<bool>? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<LazyLoadPauseScope>()
        ?.notifier;
  }

  static bool isPaused(BuildContext context) {
    return maybeOf(context)?.value ?? false;
  }
}

class _LazyLoadCache {
  _LazyLoadCache({required this.maxEntries});

  final int maxEntries;
  final LinkedHashSet<String> _entries = LinkedHashSet<String>();

  bool contains(String key) => _entries.contains(key);

  void add(String key) {
    if (_entries.remove(key)) {
      _entries.add(key);
      return;
    }

    if (_entries.length >= maxEntries) {
      _entries.remove(_entries.first);
    }
    _entries.add(key);
  }
}
