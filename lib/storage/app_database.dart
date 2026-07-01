import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 应用级 Hive 存储初始化与通用命名 box 工厂。
class AppDatabase {
  AppDatabase._();

  static bool _initialized = false;
  static Future<void>? _initializing;
  static final Map<String, Box<Map>> _openBoxes = <String, Box<Map>>{};
  static final Map<String, Future<Box<Map>>> _openingBoxes =
      <String, Future<Box<Map>>>{};

  /// 测试可注入：跳过默认初始化路径，直接使用测试已初始化的 Hive。
  @visibleForTesting
  static void debugMarkInitialized() {
    _initialized = true;
  }

  /// 测试用：复位状态。
  @visibleForTesting
  static Future<void> debugReset() async {
    _initialized = false;
    _initializing = null;
    _openBoxes.clear();
    _openingBoxes.clear();
  }

  /// 通用命名 box 入口，供图片缓存索引等基础设施使用。
  ///
  /// [compactionStrategy] 透传给 Hive。高频覆盖写的场景（如缓存 touched
  /// 时间戳回写）需要放宽默认策略，避免频繁全文件 compaction。
  static Future<Box<Map>> namedBox(
    String name, {
    CompactionStrategy? compactionStrategy,
  }) {
    return _openNamedBox(name, compactionStrategy: compactionStrategy);
  }

  static Future<Box<Map>> _openNamedBox(
    String name, {
    CompactionStrategy? compactionStrategy,
  }) async {
    await _ensureInitialized();
    final cached = _openBoxes[name];
    if (cached != null && cached.isOpen) return cached;
    final pending = _openingBoxes[name];
    if (pending != null) return pending;
    Future<Box<Map>> openBox() {
      return compactionStrategy == null
          ? Hive.openBox<Map>(name)
          : Hive.openBox<Map>(name, compactionStrategy: compactionStrategy);
    }

    final opening = openBox();
    _openingBoxes[name] = opening;
    try {
      Box<Map>? recoveredBox;
      try {
        recoveredBox = await opening;
      } catch (error) {
        if (!_isRecoverableNamedBoxError(error)) rethrow;
        debugPrint('[AppDatabase] 检测到损坏的 Hive box，重建: $name, error=$error');
        await deleteNamedBoxFromDisk(name);
        recoveredBox = await openBox();
      }
      final box = recoveredBox;
      _openBoxes[name] = box;
      return box;
    } finally {
      _openingBoxes.remove(name);
    }
  }

  static Future<void> _ensureInitialized() {
    if (_initialized) return Future.value();
    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  static Future<void> _initialize() async {
    if (kIsWeb) {
      throw UnsupportedError('AppDatabase 暂不支持 Web 平台。');
    }
    final directory = await getApplicationDocumentsDirectory();
    Hive.init(p.join(directory.path, 'hive'));
    _initialized = true;
  }

  static Future<void> closeNamedBox(String name) async {
    _openBoxes.remove(name);
    if (Hive.isBoxOpen(name)) {
      await Hive.box<Map>(name).close();
    }
  }

  static Future<void> deleteNamedBoxFromDisk(String name) async {
    await _ensureInitialized();
    _openingBoxes.remove(name);
    _openBoxes.remove(name);
    if (Hive.isBoxOpen(name)) {
      await Hive.box<Map>(name).close();
    }
    await Hive.deleteBoxFromDisk(name);
  }

  static bool _isRecoverableNamedBoxError(Object error) {
    final message = error.toString();
    return message.contains('unknown typeId') ||
        message.contains('Cannot read');
  }
}
