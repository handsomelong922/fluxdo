import 'dart:async';

import 'package:flutter/foundation.dart';

typedef TopicPostParseWarmUpTask = FutureOr<void> Function();
typedef TopicPostParseWarmUpTaskScheduler =
    void Function(TopicPostParseWarmUpTask task);
typedef TopicPostParseWarmUp<T> =
    FutureOr<void> Function(T item, bool Function() isCurrent);

/// 详情页帖子解析预热的顺序调度队列。
///
/// 每次 [start] 都会开启新一代任务；旧代已经排入调度器或 Timer 的回调
/// 会在执行前失效。滚动繁忙时不消费队列，等待空闲后从原位置继续。
class TopicPostParseWarmUpQueue<T> {
  TopicPostParseWarmUpQueue({
    required bool Function() isBusy,
    required TopicPostParseWarmUpTaskScheduler scheduleTask,
    required TopicPostParseWarmUp<T> warmUp,
    Duration busyRetryDelay = const Duration(milliseconds: 400),
  }) : _isBusy = isBusy,
       _scheduleTask = scheduleTask,
       _warmUp = warmUp,
       _busyRetryDelay = busyRetryDelay;

  final bool Function() _isBusy;
  final TopicPostParseWarmUpTaskScheduler _scheduleTask;
  final TopicPostParseWarmUp<T> _warmUp;
  final Duration _busyRetryDelay;

  List<T> _items = <T>[];
  int _index = 0;
  int _generation = 0;
  Timer? _retryTimer;

  @visibleForTesting
  int get pendingCount => _items.length - _index;

  void start(Iterable<T> items) {
    final nextItems = List<T>.of(items, growable: false);
    if (nextItems.isEmpty) return;

    final generation = ++_generation;
    _retryTimer?.cancel();
    _retryTimer = null;
    _items = nextItems;
    _index = 0;
    _scheduleNext(generation);
  }

  void cancel() {
    _generation++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _items = <T>[];
    _index = 0;
  }

  void _scheduleNext(int generation) {
    _scheduleTask(() async {
      if (generation != _generation || _index >= _items.length) return;
      if (_isBusy()) {
        _scheduleRetry(generation);
        return;
      }

      final item = _items[_index++];
      try {
        await _warmUp(item, () => generation == _generation);
      } catch (_) {
        // 预热失败不影响正式渲染，继续处理后续队列。
      }

      if (generation == _generation && _index < _items.length) {
        _scheduleNext(generation);
      }
    });
  }

  void _scheduleRetry(int generation) {
    _retryTimer?.cancel();
    _retryTimer = Timer(_busyRetryDelay, () {
      _retryTimer = null;
      if (generation != _generation) return;
      _scheduleNext(generation);
    });
  }
}
