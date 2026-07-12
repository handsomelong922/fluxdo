import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PerformanceFrameSeverity { good, slow, jank, severe, frozen }

extension PerformanceFrameSeverityLabel on PerformanceFrameSeverity {
  String get label {
    return switch (this) {
      PerformanceFrameSeverity.good => 'good',
      PerformanceFrameSeverity.slow => 'slow',
      PerformanceFrameSeverity.jank => 'jank',
      PerformanceFrameSeverity.severe => 'severe',
      PerformanceFrameSeverity.frozen => 'frozen',
    };
  }
}

class PerformanceFrameAttribution {
  PerformanceFrameAttribution({
    Map<String, int> builds = const <String, int>{},
    List<Map<String, Object?>> works = const <Map<String, Object?>>[],
    List<Map<String, Object?>> events = const <Map<String, Object?>>[],
    this.droppedBuildLabels = 0,
    this.droppedWorks = 0,
    this.droppedEvents = 0,
  }) : builds = LinkedHashMap<String, int>.of(builds),
       works = List<Map<String, Object?>>.of(works),
       events = List<Map<String, Object?>>.of(events);

  final LinkedHashMap<String, int> builds;
  final List<Map<String, Object?>> works;
  final List<Map<String, Object?>> events;
  int droppedBuildLabels;
  int droppedWorks;
  int droppedEvents;

  bool get hasImageEvent => events.any(
    (event) => event['label']?.toString().startsWith('image:') ?? false,
  );

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (builds.isNotEmpty) 'builds': builds,
      if (works.isNotEmpty) 'works': works,
      if (events.isNotEmpty) 'events': events,
      if (droppedBuildLabels > 0) 'droppedBuildLabels': droppedBuildLabels,
      if (droppedWorks > 0) 'droppedWorks': droppedWorks,
      if (droppedEvents > 0) 'droppedEvents': droppedEvents,
    };
  }
}

/// 只在性能诊断开启时使用的帧内归因缓冲。
///
/// 按 engine frame number 聚合，容量和每帧条目数均有上限；正常关闭状态
/// 不会调用它，也不会产生列表滚动热路径写盘。
class PerformanceFrameAttributionBuffer {
  PerformanceFrameAttributionBuffer({
    this.maxFrames = 96,
    this.maxBuildLabelsPerFrame = 24,
    this.maxWorksPerFrame = 12,
    this.maxEventsPerFrame = 12,
  });

  final int maxFrames;
  final int maxBuildLabelsPerFrame;
  final int maxWorksPerFrame;
  final int maxEventsPerFrame;
  final LinkedHashMap<int, PerformanceFrameAttribution> _frames =
      LinkedHashMap<int, PerformanceFrameAttribution>();

  int get length => _frames.length;

  void noteBuild({required int frameNumber, required String label}) {
    final frame = _frame(frameNumber);
    final previous = frame.builds[label];
    if (previous != null) {
      frame.builds[label] = previous + 1;
      return;
    }
    if (frame.builds.length >= maxBuildLabelsPerFrame) {
      frame.droppedBuildLabels++;
      return;
    }
    frame.builds[label] = 1;
  }

  void noteWork({
    required int frameNumber,
    required String label,
    required int elapsedMicros,
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    final frame = _frame(frameNumber);
    if (frame.works.length >= maxWorksPerFrame) {
      frame.droppedWorks++;
      return;
    }
    frame.works.add(<String, Object?>{
      'label': label,
      'elapsedMicros': elapsedMicros,
      ...data,
    });
  }

  void noteEvent({
    required int frameNumber,
    required String label,
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    final frame = _frame(frameNumber);
    if (frame.events.length >= maxEventsPerFrame) {
      frame.droppedEvents++;
      return;
    }
    frame.events.add(<String, Object?>{'label': label, ...data});
  }

  PerformanceFrameAttribution? take(int frameNumber) {
    return _frames.remove(frameNumber);
  }

  void clear() => _frames.clear();

  PerformanceFrameAttribution _frame(int frameNumber) {
    final existing = _frames[frameNumber];
    if (existing != null) return existing;
    final created = PerformanceFrameAttribution();
    _frames[frameNumber] = created;
    while (_frames.length > maxFrames) {
      _frames.remove(_frames.keys.first);
    }
    return created;
  }
}

/// 设备端性能诊断采集器。
///
/// 默认关闭；开启后只记录慢帧、路由、滚动、触摸、生命周期和资源快照，
/// 避免在正常浏览时产生额外写盘开销。
class PerformanceDiagnosticsService extends ChangeNotifier {
  PerformanceDiagnosticsService._();

  static final PerformanceDiagnosticsService instance =
      PerformanceDiagnosticsService._();

  static const String prefEnabledKey = 'pref_performance_diagnostics_enabled';
  static const int maxTraceEntries = 2000;
  static const int maxTraceBytes = 3 * 1024 * 1024;
  static const int _retentionSlack = 100;
  static const int _slowFrameMs = 17;
  static const int _jankFrameMs = 34;
  static const int _severeFrameMs = 50;
  static const int _frozenFrameMs = 100;
  static const int _buildOrRasterJankMs = 24;
  static const int _buildOrRasterSlowMs = 12;
  static const int _recentEventLimit = 24;
  static const Duration _uiHeartbeatInterval = Duration(milliseconds: 100);
  static const Duration _uiStallThreshold = Duration(milliseconds: 40);
  static const Duration _traceFlushDelay = Duration(milliseconds: 250);
  static const int _traceFlushBytes = 16 * 1024;

  SharedPreferences? _prefs;
  bool _enabled = false;
  bool _timingsAttached = false;
  String? _sessionId;
  DateTime? _sessionStartedAt;
  File? _logFile;
  Future<void> _writeChain = Future.value();
  final List<String> _pendingTraceLines = <String>[];
  int _pendingTraceBytes = 0;
  Timer? _traceFlushTimer;
  bool _suppressTraceWrites = false;
  int? _cachedEntryCount;
  Map<String, Object?>? _currentRoute;
  String? _lastLifecycleState;
  final Map<PerformanceFrameSeverity, DateTime> _lastFrameSampleAt =
      <PerformanceFrameSeverity, DateTime>{};
  DateTime? _frameWindowStartedAt;
  int _frameWindowCount = 0;
  int _frameWindowSlowCount = 0;
  int _frameWindowJankCount = 0;
  int _frameWindowFrozenCount = 0;
  int _frameWindowWorstMs = 0;
  int _frameWindowTotalMs = 0;
  int _slowFrameStreak = 0;
  Timer? _uiHeartbeatTimer;
  DateTime? _nextUiHeartbeatAt;
  final ListQueue<Map<String, Object?>> _recentEvents =
      ListQueue<Map<String, Object?>>();
  final PerformanceFrameAttributionBuffer _attributionBuffer =
      PerformanceFrameAttributionBuffer();

  bool get enabled => _enabled;

  String get statusDescription {
    if (!_enabled) {
      return '已关闭 · 不记录性能追踪';
    }
    return '已开启 · 慢帧、组件归因、滚动和资源快照会写入 performance_trace.jsonl';
  }

  void initialize(SharedPreferences prefs) {
    _prefs = prefs;
    _enabled = prefs.getBool(prefEnabledKey) ?? false;
    if (_enabled) {
      _startSession(reason: 'initialize');
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    if (value) {
      _enabled = true;
      await _prefs?.setBool(prefEnabledKey, true);
      _startSession(reason: 'user_enabled');
      notifyListeners();
      return;
    }

    _writeTrace(
      type: 'diagnostics',
      event: 'disabled',
      data: _buildSnapshot(includeRecentEvents: true),
      force: true,
    );
    _enabled = false;
    _detachTimingsCallback();
    _stopUiHeartbeat();
    _attributionBuffer.clear();
    await _flushPendingWrites();
    await _prefs?.setBool(prefEnabledKey, false);
    notifyListeners();
  }

  /// 标记当前 engine 帧正在构建的重组件。关闭诊断时为空操作。
  void noteBuild(String component, {int? id}) {
    if (!_enabled) return;
    _attributionBuffer.noteBuild(
      frameNumber: _currentFrameNumber,
      label: id == null ? component : '$component#$id',
    );
  }

  /// 记录当前帧发生的图片上屏等有限事件。关闭诊断时为空操作。
  void noteFrameEvent(
    String label, {
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    if (!_enabled) return;
    _attributionBuffer.noteEvent(
      frameNumber: _currentFrameNumber,
      label: label,
      data: data,
    );
  }

  /// 仅在诊断开启时创建 Stopwatch，避免关闭状态产生对象分配。
  Stopwatch? startSyncWork() {
    if (!_enabled) return null;
    return Stopwatch()..start();
  }

  /// 把超过阈值的同步工作挂到完成时所在的 engine 帧。
  void finishSyncWork(
    Stopwatch? stopwatch, {
    required String label,
    Duration threshold = const Duration(milliseconds: 4),
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    if (stopwatch == null || !_enabled) return;
    stopwatch.stop();
    if (stopwatch.elapsed < threshold) return;
    _attributionBuffer.noteWork(
      frameNumber: _currentFrameNumber,
      label: label,
      elapsedMicros: stopwatch.elapsedMicroseconds,
      data: data,
    );
  }

  void recordInteraction(
    String event, {
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    if (!_enabled) return;
    _recordEvent(type: 'interaction', event: event, data: data);
  }

  void recordRoute({
    required String event,
    required Route<dynamic>? route,
    Route<dynamic>? previousRoute,
  }) {
    if (!_enabled) return;
    final routeInfo = _routeInfo(route);
    final previousRouteInfo = _routeInfo(previousRoute);
    if (event == 'push' || event == 'replace') {
      _currentRoute = routeInfo;
    } else if (event == 'pop') {
      _currentRoute = previousRouteInfo ?? routeInfo;
    }
    final data = <String, Object?>{};
    if (routeInfo != null) {
      data['route'] = routeInfo;
    }
    if (previousRouteInfo != null) {
      data['previousRoute'] = previousRouteInfo;
    }
    _recordEvent(type: 'route', event: event, data: data, important: true);
  }

  void recordLifecycle(AppLifecycleState state) {
    if (!_enabled) return;
    _lastLifecycleState = state.name;
    _recordEvent(
      type: 'lifecycle',
      event: 'app_lifecycle',
      data: <String, Object?>{'state': state.name},
      important: true,
    );
  }

  void recordMemoryPressure({required String stage}) {
    if (!_enabled) return;
    _recordEvent(
      type: 'runtime',
      event: 'memory_pressure',
      data: <String, Object?>{
        'stage': stage,
        'snapshot': _buildSnapshot(includeRecentEvents: true),
      },
      important: true,
    );
  }

  void recordCacheMaintenance({required String event, required String reason}) {
    if (!_enabled) return;
    _recordEvent(
      type: 'runtime',
      event: event,
      data: <String, Object?>{
        'reason': reason,
        'snapshot': _buildSnapshot(includeRecentEvents: false),
      },
      important: true,
    );
  }

  void markCurrentJank({String source = 'manual'}) {
    if (!_enabled) return;
    _recordEvent(
      type: 'marker',
      event: 'manual_jank_marker',
      data: <String, Object?>{
        'source': source,
        'snapshot': _buildSnapshot(includeRecentEvents: true),
      },
      important: true,
    );
  }

  static PerformanceFrameSeverity classifyFrame({
    required int totalMs,
    required int buildMs,
    required int rasterMs,
  }) {
    if (totalMs >= _frozenFrameMs) return PerformanceFrameSeverity.frozen;
    if (totalMs >= _severeFrameMs) return PerformanceFrameSeverity.severe;
    if (totalMs >= _jankFrameMs ||
        buildMs >= _buildOrRasterJankMs ||
        rasterMs >= _buildOrRasterJankMs) {
      return PerformanceFrameSeverity.jank;
    }
    if (totalMs >= _slowFrameMs ||
        buildMs >= _buildOrRasterSlowMs ||
        rasterMs >= _buildOrRasterSlowMs) {
      return PerformanceFrameSeverity.slow;
    }
    return PerformanceFrameSeverity.good;
  }

  @visibleForTesting
  static Duration frameSampleInterval(PerformanceFrameSeverity severity) {
    return switch (severity) {
      PerformanceFrameSeverity.good => Duration.zero,
      PerformanceFrameSeverity.slow => const Duration(seconds: 1),
      PerformanceFrameSeverity.jank => const Duration(milliseconds: 300),
      PerformanceFrameSeverity.severe => const Duration(milliseconds: 150),
      PerformanceFrameSeverity.frozen => Duration.zero,
    };
  }

  @visibleForTesting
  static bool shouldSampleFrame({
    required PerformanceFrameSeverity severity,
    required DateTime now,
    DateTime? lastSampleAt,
  }) {
    if (severity == PerformanceFrameSeverity.good) return false;
    if (severity == PerformanceFrameSeverity.frozen) return true;
    if (lastSampleAt == null) return true;
    return now.difference(lastSampleAt) >= frameSampleInterval(severity);
  }

  static String classifyDominantPhase({
    required int buildMs,
    required int rasterMs,
    required int vsyncOverheadMs,
    required int queueWaitMs,
  }) {
    final phases = <String, int>{
      'build': buildMs,
      'raster': rasterMs,
      'vsync_overhead': vsyncOverheadMs,
      'pipeline_wait': queueWaitMs,
    };
    return phases.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static String? buildAttributionHint({
    required int buildMs,
    required int rasterMs,
    required PerformanceFrameAttribution? attribution,
  }) {
    if (buildMs >= _buildOrRasterSlowMs &&
        (attribution == null || attribution.builds.isEmpty)) {
      return 'build_slow_without_component_notes';
    }
    if (rasterMs >= _buildOrRasterSlowMs &&
        (attribution == null || !attribution.hasImageEvent)) {
      return 'raster_slow_without_image_events';
    }
    return null;
  }

  @visibleForTesting
  static List<String> retainedTraceLines(
    List<String> lines, {
    int maxEntries = maxTraceEntries,
    int maxBytes = maxTraceBytes,
  }) {
    final normalized = lines
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) return const <String>[];

    final retained = <String>[];
    var bytes = 0;
    for (final line in normalized.reversed) {
      final lineBytes = utf8.encode(line).length + 1;
      if (retained.length >= maxEntries) break;
      if (retained.isNotEmpty && bytes + lineBytes > maxBytes) break;
      retained.add(line);
      bytes += lineBytes;
    }
    return retained.reversed.toList(growable: false);
  }

  Future<String?> readLogs() async {
    await _flushPendingWrites();
    final file = await _getLogFile();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  Future<String?> getLogPath() async {
    final file = await _getLogFile();
    return file.path;
  }

  Future<void> clear() async {
    _suppressTraceWrites = true;
    try {
      await _flushPendingWrites();
      _writeChain = _writeChain.then((_) async {
        final file = await _getLogFile();
        await file.writeAsString('');
        _cachedEntryCount = 0;
      });
      await _writeChain;
      _recentEvents.clear();
    } finally {
      _suppressTraceWrites = false;
    }
    if (_enabled) {
      _writeTrace(
        type: 'diagnostics',
        event: 'cleared',
        data: _buildSnapshot(includeRecentEvents: false),
        force: true,
      );
      await _flushPendingWrites();
    }
  }

  void _startSession({required String reason}) {
    _sessionId = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    _sessionStartedAt = DateTime.now();
    _resetFrameWindow();
    _attributionBuffer.clear();
    _attachTimingsCallback();
    _startUiHeartbeat();
    _writeTrace(
      type: 'diagnostics',
      event: 'enabled',
      data: <String, Object?>{
        'reason': reason,
        'snapshot': _buildSnapshot(includeRecentEvents: false),
      },
      force: true,
    );
  }

  void _attachTimingsCallback() {
    if (_timingsAttached) return;
    SchedulerBinding.instance.addTimingsCallback(_handleFrameTimings);
    _timingsAttached = true;
  }

  void _detachTimingsCallback() {
    if (!_timingsAttached) return;
    SchedulerBinding.instance.removeTimingsCallback(_handleFrameTimings);
    _timingsAttached = false;
  }

  void _handleFrameTimings(List<ui.FrameTiming> timings) {
    if (!_enabled) return;
    final now = DateTime.now();
    for (final timing in timings) {
      final buildMs = _durationMs(timing.buildDuration);
      final rasterMs = _durationMs(timing.rasterDuration);
      final totalMs = _durationMs(timing.totalSpan);
      final vsyncOverheadMs = _durationMs(timing.vsyncOverhead);
      final queueWaitMicros =
          timing.timestampInMicroseconds(ui.FramePhase.rasterStart) -
          timing.timestampInMicroseconds(ui.FramePhase.buildFinish);
      final queueWaitMs = queueWaitMicros <= 0
          ? 0
          : (queueWaitMicros / 1000).round();
      final attribution = _attributionBuffer.take(timing.frameNumber);
      final severity = classifyFrame(
        totalMs: totalMs,
        buildMs: buildMs,
        rasterMs: rasterMs,
      );

      _updateFrameWindow(totalMs: totalMs, severity: severity);
      if (severity == PerformanceFrameSeverity.good) {
        _slowFrameStreak = 0;
        continue;
      }

      _slowFrameStreak++;
      if (!_shouldWriteFrameSample(severity, now)) continue;
      _lastFrameSampleAt[severity] = now;

      _writeTrace(
        type: 'frame',
        event: 'slow_frame',
        data: <String, Object?>{
          'severity': severity.label,
          'totalMs': totalMs,
          'buildMs': buildMs,
          'rasterMs': rasterMs,
          'vsyncOverheadMs': vsyncOverheadMs,
          'queueWaitMs': queueWaitMs,
          'dominantPhase': classifyDominantPhase(
            buildMs: buildMs,
            rasterMs: rasterMs,
            vsyncOverheadMs: vsyncOverheadMs,
            queueWaitMs: queueWaitMs,
          ),
          'frameNumber': timing.frameNumber,
          'slowFrameStreak': _slowFrameStreak,
          'layerCacheCount': timing.layerCacheCount,
          'layerCacheBytes': timing.layerCacheBytes,
          'pictureCacheCount': timing.pictureCacheCount,
          'pictureCacheBytes': timing.pictureCacheBytes,
          if (attribution case final attribution?)
            'attribution': attribution.toJson(),
          'attributionHint': ?buildAttributionHint(
            buildMs: buildMs,
            rasterMs: rasterMs,
            attribution: attribution,
          ),
          'snapshot': _buildSnapshot(
            includeRecentEvents:
                severity.index >= PerformanceFrameSeverity.severe.index,
          ),
        },
      );
    }
    _flushFrameWindowIfNeeded(now);
  }

  int get _currentFrameNumber =>
      WidgetsBinding.instance.platformDispatcher.frameData.frameNumber;

  void _startUiHeartbeat() {
    _stopUiHeartbeat();
    _nextUiHeartbeatAt = DateTime.now().add(_uiHeartbeatInterval);
    _uiHeartbeatTimer = Timer.periodic(_uiHeartbeatInterval, (_) {
      if (!_enabled) return;
      final now = DateTime.now();
      final expected = _nextUiHeartbeatAt ?? now;
      final drift = now.difference(expected);
      _nextUiHeartbeatAt = now.add(_uiHeartbeatInterval);
      if (drift < _uiStallThreshold) return;
      _recordEvent(
        type: 'runtime',
        event: 'ui_isolate_stall',
        data: <String, Object?>{
          'driftMs': drift.inMilliseconds,
          'snapshot': _buildSnapshot(includeRecentEvents: true),
        },
        important: true,
      );
    });
  }

  void _stopUiHeartbeat() {
    _uiHeartbeatTimer?.cancel();
    _uiHeartbeatTimer = null;
    _nextUiHeartbeatAt = null;
  }

  bool _shouldWriteFrameSample(
    PerformanceFrameSeverity severity,
    DateTime now,
  ) {
    return shouldSampleFrame(
      severity: severity,
      now: now,
      lastSampleAt: _lastFrameSampleAt[severity],
    );
  }

  void _updateFrameWindow({
    required int totalMs,
    required PerformanceFrameSeverity severity,
  }) {
    _frameWindowStartedAt ??= DateTime.now();
    _frameWindowCount++;
    _frameWindowTotalMs += totalMs;
    if (totalMs > _frameWindowWorstMs) {
      _frameWindowWorstMs = totalMs;
    }
    if (severity.index >= PerformanceFrameSeverity.slow.index) {
      _frameWindowSlowCount++;
    }
    if (severity.index >= PerformanceFrameSeverity.jank.index) {
      _frameWindowJankCount++;
    }
    if (severity == PerformanceFrameSeverity.frozen) {
      _frameWindowFrozenCount++;
    }
  }

  void _flushFrameWindowIfNeeded(DateTime now) {
    final startedAt = _frameWindowStartedAt;
    if (startedAt == null) return;
    if (now.difference(startedAt) < const Duration(seconds: 5)) return;
    if (_frameWindowCount == 0) return;

    _writeTrace(
      type: 'frame',
      event: 'frame_window',
      data: <String, Object?>{
        'durationMs': now.difference(startedAt).inMilliseconds,
        'frames': _frameWindowCount,
        'slowFrames': _frameWindowSlowCount,
        'jankFrames': _frameWindowJankCount,
        'frozenFrames': _frameWindowFrozenCount,
        'worstMs': _frameWindowWorstMs,
        'averageMs': (_frameWindowTotalMs / _frameWindowCount).toStringAsFixed(
          1,
        ),
        'snapshot': _buildSnapshot(includeRecentEvents: false),
      },
    );
    _resetFrameWindow();
  }

  void _resetFrameWindow() {
    _frameWindowStartedAt = DateTime.now();
    _frameWindowCount = 0;
    _frameWindowSlowCount = 0;
    _frameWindowJankCount = 0;
    _frameWindowFrozenCount = 0;
    _frameWindowWorstMs = 0;
    _frameWindowTotalMs = 0;
    _slowFrameStreak = 0;
    _lastFrameSampleAt.clear();
  }

  int _durationMs(Duration duration) {
    return (duration.inMicroseconds / 1000).round();
  }

  void _recordEvent({
    required String type,
    required String event,
    required Map<String, Object?> data,
    bool important = false,
  }) {
    final recent = <String, Object?>{
      'timestamp': DateTime.now().toIso8601String(),
      'type': type,
      'event': event,
      if (data.isNotEmpty) 'data': _compactForRecent(data),
    };
    _recentEvents.add(recent);
    while (_recentEvents.length > _recentEventLimit) {
      _recentEvents.removeFirst();
    }
    _writeTrace(type: type, event: event, data: data, force: important);
  }

  void _writeTrace({
    required String type,
    required String event,
    required Map<String, Object?> data,
    bool force = false,
  }) {
    if (_suppressTraceWrites || (!_enabled && !force)) return;
    final now = DateTime.now();
    final entry = <String, Object?>{
      'timestamp': now.toIso8601String(),
      'sessionId': _sessionId,
      'sessionAgeMs': _sessionAgeMs(now),
      'type': type,
      'event': event,
      ...data,
    };
    final line = '${jsonEncode(entry)}\n';
    _pendingTraceLines.add(line);
    _pendingTraceBytes += line.length;
    if (force || _pendingTraceBytes >= _traceFlushBytes) {
      unawaited(_flushPendingWrites());
      return;
    }
    _traceFlushTimer ??= Timer(_traceFlushDelay, () {
      unawaited(_flushPendingWrites());
    });
  }

  Future<void> _flushPendingWrites() {
    _traceFlushTimer?.cancel();
    _traceFlushTimer = null;
    if (_pendingTraceLines.isEmpty) return _writeChain;

    final batch = _pendingTraceLines.join();
    final entryCount = _pendingTraceLines.length;
    _pendingTraceLines.clear();
    _pendingTraceBytes = 0;
    _writeChain = _writeChain.then((_) => _writeBatch(batch, entryCount));
    return _writeChain;
  }

  Future<void> _writeBatch(String batch, int entryCount) async {
    try {
      final file = await _getLogFile();
      await _loadEntryCountIfNeeded(file);
      await file.writeAsString(batch, mode: FileMode.append);
      _cachedEntryCount = (_cachedEntryCount ?? 0) + entryCount;
      await _enforceRetentionIfNeeded(file);
    } catch (_) {
      // 诊断写盘失败不能影响正常浏览。
    }
  }

  Future<File> _getLogFile() async {
    final cached = _logFile;
    if (cached != null) return cached;
    final dir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${dir.path}/logs');
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }
    return _logFile = File('${logDir.path}/performance_trace.jsonl');
  }

  Future<void> _loadEntryCountIfNeeded(File file) async {
    if (_cachedEntryCount != null) return;
    if (!await file.exists()) {
      _cachedEntryCount = 0;
      return;
    }
    final content = await file.readAsString();
    _cachedEntryCount = content
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .length;
  }

  Future<void> _enforceRetentionIfNeeded(File file) async {
    if (!await file.exists()) return;
    final entryCount = _cachedEntryCount ?? 0;
    final fileSize = await file.length();
    if (entryCount <= maxTraceEntries + _retentionSlack &&
        fileSize < maxTraceBytes) {
      return;
    }
    final content = await file.readAsString();
    final retained = retainedTraceLines(content.split('\n'));
    await file.writeAsString(
      retained.isEmpty ? '' : '${retained.join('\n')}\n',
    );
    _cachedEntryCount = retained.length;
  }

  int? _sessionAgeMs(DateTime now) {
    final startedAt = _sessionStartedAt;
    if (startedAt == null) return null;
    return now.difference(startedAt).inMilliseconds;
  }

  Map<String, Object?> _buildSnapshot({required bool includeRecentEvents}) {
    final cache = PaintingBinding.instance.imageCache;
    final views = ui.PlatformDispatcher.instance.views;
    final display = views.isEmpty ? null : views.first.display;
    return <String, Object?>{
      if (_currentRoute != null) 'currentRoute': _currentRoute,
      if (_lastLifecycleState != null) 'lifecycleState': _lastLifecycleState,
      if (display != null)
        'display': <String, Object?>{
          'refreshRate': display.refreshRate.toStringAsFixed(1),
          'devicePixelRatio': display.devicePixelRatio.toStringAsFixed(2),
          'physicalWidth': display.size.width.round(),
          'physicalHeight': display.size.height.round(),
        },
      'imageCache': <String, Object?>{
        'currentSize': cache.currentSize,
        'currentSizeBytes': cache.currentSizeBytes,
        'liveImageCount': cache.liveImageCount,
        'pendingImageCount': cache.pendingImageCount,
        'maximumSize': cache.maximumSize,
        'maximumSizeBytes': cache.maximumSizeBytes,
      },
      if (includeRecentEvents)
        'recentEvents': _recentEvents.toList(growable: false),
    };
  }

  Map<String, Object?>? _routeInfo(Route<dynamic>? route) {
    if (route == null) return null;
    final settings = route.settings;
    return <String, Object?>{
      'name': settings.name ?? route.runtimeType.toString(),
      'runtimeType': route.runtimeType.toString(),
      if (settings.arguments != null)
        'arguments': _sanitizeArguments(settings.arguments),
    };
  }

  Object? _sanitizeArguments(Object? arguments) {
    if (arguments is Map) {
      return Map<String, Object?>.fromEntries(
        arguments.entries.map((entry) {
          return MapEntry(
            entry.key.toString(),
            _sanitizeArgumentValue(entry.value),
          );
        }),
      );
    }
    return _sanitizeArgumentValue(arguments);
  }

  Object? _sanitizeArgumentValue(Object? value) {
    if (value == null || value is num || value is bool) return value;
    if (value is String) {
      return value.length <= 160 ? value : '${value.substring(0, 160)}...';
    }
    return value.runtimeType.toString();
  }

  Map<String, Object?> _compactForRecent(Map<String, Object?> data) {
    final compact = Map<String, Object?>.of(data);
    compact.remove('snapshot');
    return compact;
  }
}

class PerformanceDiagnosticsRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    PerformanceDiagnosticsService.instance.recordRoute(
      event: 'push',
      route: route,
      previousRoute: previousRoute,
    );
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    PerformanceDiagnosticsService.instance.recordRoute(
      event: 'pop',
      route: route,
      previousRoute: previousRoute,
    );
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    PerformanceDiagnosticsService.instance.recordRoute(
      event: 'remove',
      route: route,
      previousRoute: previousRoute,
    );
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    PerformanceDiagnosticsService.instance.recordRoute(
      event: 'replace',
      route: newRoute,
      previousRoute: oldRoute,
    );
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

final PerformanceDiagnosticsRouteObserver performanceDiagnosticsRouteObserver =
    PerformanceDiagnosticsRouteObserver();

class PerformanceDiagnosticsListener extends StatefulWidget {
  const PerformanceDiagnosticsListener({super.key, required this.child});

  final Widget child;

  @override
  State<PerformanceDiagnosticsListener> createState() =>
      _PerformanceDiagnosticsListenerState();
}

class _PerformanceDiagnosticsListenerState
    extends State<PerformanceDiagnosticsListener> {
  DateTime? _lastScrollUpdateAt;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: widget.child,
      ),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    PerformanceDiagnosticsService.instance.recordInteraction(
      'pointer_down',
      data: _pointerData(event.kind, event.buttons, event.position),
    );
  }

  void _handlePointerUp(PointerUpEvent event) {
    PerformanceDiagnosticsService.instance.recordInteraction(
      'pointer_up',
      data: _pointerData(event.kind, event.buttons, event.position),
    );
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    PerformanceDiagnosticsService.instance.recordInteraction(
      'pointer_cancel',
      data: _pointerData(event.kind, event.buttons, event.position),
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    final service = PerformanceDiagnosticsService.instance;
    if (!service.enabled) return false;

    if (notification is ScrollStartNotification) {
      service.recordInteraction(
        'scroll_start',
        data: _scrollData(notification.metrics),
      );
      return false;
    }
    if (notification is ScrollEndNotification) {
      service.recordInteraction(
        'scroll_end',
        data: _scrollData(notification.metrics),
      );
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      final now = DateTime.now();
      final last = _lastScrollUpdateAt;
      if (last == null ||
          now.difference(last) >= const Duration(milliseconds: 700)) {
        _lastScrollUpdateAt = now;
        service.recordInteraction(
          'scroll_update',
          data: <String, Object?>{
            ..._scrollData(notification.metrics),
            if (notification.scrollDelta != null)
              'delta': _roundDouble(notification.scrollDelta!),
          },
        );
      }
    }
    if (notification is UserScrollNotification) {
      service.recordInteraction(
        'scroll_direction',
        data: <String, Object?>{
          ..._scrollData(notification.metrics),
          'direction': notification.direction.name,
        },
      );
    }
    return false;
  }

  Map<String, Object?> _pointerData(
    PointerDeviceKind kind,
    int buttons,
    Offset position,
  ) {
    return <String, Object?>{
      'kind': kind.name,
      'buttons': buttons,
      'x': _roundDouble(position.dx),
      'y': _roundDouble(position.dy),
    };
  }

  Map<String, Object?> _scrollData(ScrollMetrics metrics) {
    return <String, Object?>{
      'axis': metrics.axis.name,
      'pixels': _roundDouble(metrics.pixels),
      'min': _roundDouble(metrics.minScrollExtent),
      'max': _roundDouble(metrics.maxScrollExtent),
      'viewport': _roundDouble(metrics.viewportDimension),
      'before': _roundDouble(metrics.extentBefore),
      'after': _roundDouble(metrics.extentAfter),
    };
  }

  double _roundDouble(double value) {
    return double.parse(value.toStringAsFixed(1));
  }
}
