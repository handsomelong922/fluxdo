import 'package:flutter/foundation.dart';

import '../../log/log_writer.dart';
import '../../log/runtime_log_settings.dart';

/// Cookie 模块统一结构化日志。
///
/// 所有 cookie 操作通过此类记录，同时写入 debugPrint（开发调试）
/// 和 LogWriter（持久化 JSONL，用于线上排查）。
class CookieLogger {
  CookieLogger._();

  static void _debug(String message) {
    if (RuntimeLogSettings.emitVerboseConsoleDiagnostics) {
      debugPrint(message);
    }
  }

  static bool _shouldPersist(String level) {
    return RuntimeLogSettings.shouldPersistDiagnosticEvent(level: level);
  }

  // ---------------------------------------------------------------------------
  // 保存
  // ---------------------------------------------------------------------------

  /// cookie 写入 jar
  static void save({
    required String name,
    String? domain,
    bool? hostOnly,
    required String source,
    required int valueLength,
    bool replaced = false,
  }) {
    final msg =
        '$name, domain=${domain ?? '<null>'}, '
        'hostOnly=$hostOnly, source=$source, len=$valueLength'
        '${replaced ? ', replaced=true' : ''}';
    _debug('[Cookie:Save] $msg');
    if (!_shouldPersist('info')) return;
    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'info',
      'type': 'cookie_trace',
      'event': 'cookie_save',
      'message': msg,
      'name': name,
      'domain': domain,
      'hostOnly': hostOnly,
      'source': source,
      'valueLength': valueLength,
      'replaced': replaced,
    });
  }

  // ---------------------------------------------------------------------------
  // 加载
  // ---------------------------------------------------------------------------

  /// 请求发送前加载 cookie
  static void load({
    required String url,
    required int count,
    required List<String> names,
  }) {
    _debug('[Cookie:Load] $url, count=$count, names=$names');
  }

  // ---------------------------------------------------------------------------
  // 边界同步
  // ---------------------------------------------------------------------------

  /// WebView → jar 边界同步
  static void sync({
    required String direction,
    required int count,
    required List<String> names,
    required String source,
    String? url,
    List<Map<String, dynamic>>? cookieDetails,
    Map<String, dynamic>? extraFields,
  }) {
    final msg =
        '$direction, count=$count, names=$names'
        '${url != null ? ', url=$url' : ''}';
    _debug('[Cookie:Sync] $msg');
    if (!_shouldPersist('info')) return;
    final entry = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'info',
      'type': 'cookie_trace',
      'event': 'cookie_sync',
      'message': msg,
      'direction': direction,
      'count': count,
      'names': names,
      'source': source,
      'url': url,
      ...?(cookieDetails != null ? {'cookieDetails': cookieDetails} : null),
    };
    if (extraFields != null && extraFields.isNotEmpty) {
      entry.addAll(extraFields);
    }
    LogWriter.instance.write(entry);
  }

  // ---------------------------------------------------------------------------
  // 队列
  // ---------------------------------------------------------------------------

  /// 原始头入队
  static void enqueue({
    required String name,
    required String url,
    required int queueSize,
  }) {
    _debug('[Cookie:Queue] enqueue $name for $url, queueSize=$queueSize');
  }

  /// 队列 flush 到 WebView
  static void flush({required int queued, required int written}) {
    final msg = 'queued=$queued, written=$written';
    _debug('[Cookie:Flush] $msg');
    if (!_shouldPersist('info')) return;
    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'info',
      'type': 'cookie_trace',
      'event': 'cookie_flush',
      'message': msg,
      'queued': queued,
      'written': written,
    });
  }

  // ---------------------------------------------------------------------------
  // 删除 / 清理
  // ---------------------------------------------------------------------------

  /// cookie 删除
  static void delete({required String name, required String source}) {
    _debug('[Cookie:Delete] $name, source=$source');
    if (!_shouldPersist('info')) return;
    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'info',
      'type': 'cookie_trace',
      'event': 'cookie_delete',
      'message': '$name, source=$source',
      'name': name,
      'source': source,
    });
  }

  // ---------------------------------------------------------------------------
  // 错误
  // ---------------------------------------------------------------------------

  /// cookie 操作错误
  static void error({required String operation, required String error}) {
    _debug('[Cookie:Error] $operation: $error');
    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'error',
      'type': 'cookie_trace',
      'event': 'cookie_error',
      'message': '$operation: $error',
      'operation': operation,
      'error': error,
    });
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 Cookie 引擎事件（设计文档 §11.2）
  // ---------------------------------------------------------------------------

  /// Sentinel sweep 事件
  /// [event]: invoked / noop / swept / failed / cancelled
  static void sweep({
    required String event,
    required String url,
    required String name,
    String? intent,
    int? variantsBefore,
    int? variantsAfter,
    String? winnerSource,
    String? reason,
    int? elapsedMs,
    int? entryGeneration,
    int? currentGeneration,
  }) {
    final level = switch (event) {
      'failed' => 'warning',
      'noop' => 'debug',
      _ => 'info',
    };
    final msg = 'sweep_$event: $name @ $url';
    _debug('[Cookie:Sweep] $msg');
    if (!_shouldPersist(level)) return;
    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': level,
      'type': 'cookie_engine',
      'event': 'sweep_$event',
      'message': msg,
      'url': url,
      'name': name,
      ...?intent != null ? {'intent': intent} : null,
      ...?variantsBefore != null ? {'variantsBefore': variantsBefore} : null,
      ...?variantsAfter != null ? {'variantsAfter': variantsAfter} : null,
      ...?winnerSource != null ? {'winnerSource': winnerSource} : null,
      ...?reason != null ? {'reason': reason} : null,
      ...?elapsedMs != null ? {'elapsedMs': elapsedMs} : null,
      ...?entryGeneration != null ? {'entryGeneration': entryGeneration} : null,
      ...?currentGeneration != null
          ? {'currentGeneration': currentGeneration}
          : null,
    });
  }

  /// Sentinel Nuclear Reset 事件
  /// [event]: triggered / completed
  static void nuclearReset({
    required String event,
    required String url,
    String? reason,
    int? primingDurationMs,
    int? totalElapsedMs,
  }) {
    final level = event == 'triggered' ? 'warning' : 'info';
    final msg = 'nuclear_reset_$event @ $url';
    _debug('[Cookie:Nuclear] $msg');
    if (!_shouldPersist(level)) return;
    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': level,
      'type': 'cookie_engine',
      'event': 'nuclear_reset_$event',
      'message': msg,
      'url': url,
      ...?reason != null ? {'reason': reason} : null,
      ...?primingDurationMs != null
          ? {'primingDurationMs': primingDurationMs}
          : null,
      ...?totalElapsedMs != null ? {'totalElapsedMs': totalElapsedMs} : null,
    });
  }

  /// WebViewCookiePriming 事件
  /// [event]: invoked / completed / failed
  static void priming({
    required String event,
    required String url,
    bool? isPrimed,
    int? cookiesInjected,
    int? durationMs,
    String? reason,
  }) {
    final level = switch (event) {
      'failed' => 'warning',
      'invoked' => 'debug',
      _ => 'info',
    };
    final msg = 'priming_$event @ $url';
    _debug('[Cookie:Priming] $msg');
    if (!_shouldPersist(level)) return;
    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': level,
      'type': 'cookie_engine',
      'event': 'priming_$event',
      'message': msg,
      'url': url,
      ...?isPrimed != null ? {'isPrimed': isPrimed} : null,
      ...?cookiesInjected != null ? {'cookiesInjected': cookiesInjected} : null,
      ...?durationMs != null ? {'durationMs': durationMs} : null,
      ...?reason != null ? {'reason': reason} : null,
    });
  }

  /// SelfHealingInterceptor 事件
  /// [event]: triggered / retry / success / failed
  static void selfHealing({
    required String event,
    required String url,
    int? status,
    bool? jarHasValidToken,
    int? attempt,
    int? attemptsUsed,
    String? finalAction,
  }) {
    final level = switch (event) {
      'failed' => 'warning',
      _ => 'info',
    };
    final msg = 'self_healing_$event @ $url';
    _debug('[Cookie:SelfHealing] $msg');
    if (!_shouldPersist(level)) return;
    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': level,
      'type': 'cookie_engine',
      'event': 'self_healing_$event',
      'message': msg,
      'url': url,
      ...?status != null ? {'status': status} : null,
      ...?jarHasValidToken != null
          ? {'jarHasValidToken': jarHasValidToken}
          : null,
      ...?attempt != null ? {'attempt': attempt} : null,
      ...?attemptsUsed != null ? {'attemptsUsed': attemptsUsed} : null,
      ...?finalAction != null ? {'finalAction': finalAction} : null,
    });
  }

  /// Sentinel per-name Lock 超时事件
  static void lockTimeout({
    required String name,
    int? consecutiveCount,
    String? currentHolder,
  }) {
    final msg =
        'lock_timeout: $name'
        '${consecutiveCount != null ? ' (consecutive=$consecutiveCount)' : ''}';
    _debug('[Cookie:Lock] $msg');
    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'error',
      'type': 'cookie_engine',
      'event': 'lock_timeout',
      'message': msg,
      'name': name,
      ...?consecutiveCount != null
          ? {'consecutiveCount': consecutiveCount}
          : null,
      ...?currentHolder != null ? {'currentHolder': currentHolder} : null,
    });
  }
}
