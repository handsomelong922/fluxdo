import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// 少量直接回复自动展开；更多回复保留手动展开，避免移动端一次铺开过长。
const int autoExpandReplyThreshold = 4;

bool shouldAutoExpandReplyCount(int replyCount) {
  return replyCount > 0 && replyCount <= autoExpandReplyThreshold;
}

bool shouldAutoExpandRepliesNow({
  required int replyCount,
  required bool autoLoadRepliesPaused,
  required bool hideRepliesButton,
  required bool useReplyDialog,
}) {
  return !autoLoadRepliesPaused &&
      !hideRepliesButton &&
      !useReplyDialog &&
      shouldAutoExpandReplyCount(replyCount);
}

class AutoReplyPrefetchQueue {
  AutoReplyPrefetchQueue._();

  static final AutoReplyPrefetchQueue instance = AutoReplyPrefetchQueue._();

  final LinkedHashMap<String, Future<void> Function()> _pending =
      LinkedHashMap<String, Future<void> Function()>();
  final Set<String> _activeKeys = <String>{};
  bool _running = false;
  Completer<void>? _idleCompleter;

  void enqueue(String key, Future<void> Function() task) {
    if (_activeKeys.contains(key)) return;
    _activeKeys.add(key);
    _pending[key] = task;
    _idleCompleter ??= Completer<void>();
    _pump();
  }

  void cancel(String key) {
    final removed = _pending.remove(key);
    if (removed != null) {
      _activeKeys.remove(key);
    }
    if (!_running && _pending.isEmpty) {
      _completeIdle();
    }
  }

  @visibleForTesting
  int get debugPendingTaskCount => _pending.length;

  @visibleForTesting
  Future<void> get debugIdle => _idleCompleter?.future ?? Future.value();

  @visibleForTesting
  void clearPending() {
    _pending.clear();
    _activeKeys.clear();
    if (!_running) {
      _completeIdle();
    }
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    while (_pending.isNotEmpty) {
      final next = _pending.entries.first;
      _pending.remove(next.key);
      try {
        await next.value();
      } catch (_) {}
      _activeKeys.remove(next.key);
    }
    _running = false;
    _completeIdle();
  }

  void _completeIdle() {
    final completer = _idleCompleter;
    _idleCompleter = null;
    completer?.complete();
  }
}
