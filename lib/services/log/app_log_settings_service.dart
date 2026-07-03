import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/startup_request_recorder.dart';
import 'log_writer.dart';
import 'runtime_log_settings.dart';

@immutable
class AppLogSettings {
  const AppLogSettings({required this.enabled, required this.maxEntries});

  final bool enabled;
  final int maxEntries;

  AppLogSettings copyWith({bool? enabled, int? maxEntries}) {
    return AppLogSettings(
      enabled: enabled ?? this.enabled,
      maxEntries: maxEntries ?? this.maxEntries,
    );
  }
}

/// 应用日志总开关与保留上限。
///
/// - 控制 `app_log.jsonl`
/// - 控制启动请求耗时榜的内存记录
/// - 控制其他高频诊断日志是否允许写盘
class AppLogSettingsService extends ChangeNotifier {
  AppLogSettingsService._();

  static final AppLogSettingsService instance = AppLogSettingsService._();

  static const String prefEnabledKey = 'pref_app_logs_enabled';
  static const String prefMaxEntriesKey = 'pref_app_logs_max_entries';

  static const bool defaultEnabled = false;
  static const int minEntries = 50;
  static const int maxEntries = 300;
  static const int stepEntries = 25;
  static const int defaultMaxEntries = 100;

  SharedPreferences? _prefs;
  AppLogSettings _settings = const AppLogSettings(
    enabled: defaultEnabled,
    maxEntries: defaultMaxEntries,
  );

  AppLogSettings get settings => _settings;
  bool get enabled => _settings.enabled;
  int get retainedEntryLimit => _settings.maxEntries;

  static int normalizeMaxEntries(int value) {
    final clamped = value.clamp(minEntries, maxEntries).toInt();
    final snapped =
        ((clamped - minEntries) / stepEntries).round() * stepEntries +
        minEntries;
    return snapped.clamp(minEntries, maxEntries).toInt();
  }

  static String describeSettings(AppLogSettings settings) {
    if (!settings.enabled) {
      return '已关闭 · 启动请求耗时榜也会同步停用';
    }
    return '已开启 · 最多保留 ${settings.maxEntries} 条';
  }

  void initialize(SharedPreferences prefs) {
    _prefs = prefs;
    _settings = AppLogSettings(
      enabled: prefs.getBool(prefEnabledKey) ?? defaultEnabled,
      maxEntries: normalizeMaxEntries(
        prefs.getInt(prefMaxEntriesKey) ?? defaultMaxEntries,
      ),
    );
    _applyRuntimeSettings(clearRecorderWhenDisabled: true);
  }

  Future<void> setEnabled(bool value) async {
    if (_settings.enabled == value) return;
    _settings = _settings.copyWith(enabled: value);
    await _prefs?.setBool(prefEnabledKey, value);
    _applyRuntimeSettings(clearRecorderWhenDisabled: true);
    notifyListeners();
  }

  Future<void> setMaxEntries(int value) async {
    final normalized = normalizeMaxEntries(value);
    if (_settings.maxEntries == normalized) return;
    _settings = _settings.copyWith(maxEntries: normalized);
    await _prefs?.setInt(prefMaxEntriesKey, normalized);
    _applyRuntimeSettings(clearRecorderWhenDisabled: false);
    notifyListeners();
  }

  void refreshDeveloperMode(bool enabled) {
    RuntimeLogSettings.configure(developerModeEnabled: enabled);
  }

  void _applyRuntimeSettings({required bool clearRecorderWhenDisabled}) {
    RuntimeLogSettings.configure(
      appLogsEnabled: _settings.enabled,
      appLogEntryLimit: _settings.maxEntries,
    );
    StartupRequestRecorder.instance.configure(
      enabled: _settings.enabled,
      maxRecords: _settings.maxEntries,
      clearWhenDisabled: clearRecorderWhenDisabled,
    );
    unawaited(LogWriter.instance.applySettings());
  }
}
