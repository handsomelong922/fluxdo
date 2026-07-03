import 'dart:async';
import 'dart:collection';

/// 少量直接回复自动展开；更多回复保留手动展开，避免移动端一次铺开过长。
const int autoExpandReplyThreshold = 4;

bool shouldAutoExpandReplyCount(int replyCount) {
  return replyCount > 0 && replyCount <= autoExpandReplyThreshold;
}

class AutoReplyPrefetchQueue {
  AutoReplyPrefetchQueue._();

  static final AutoReplyPrefetchQueue instance = AutoReplyPrefetchQueue._();

  final Queue<({String key, Future<void> Function() task})> _pending =
      Queue<({String key, Future<void> Function() task})>();
  final Set<String> _pendingKeys = <String>{};
  bool _running = false;

  void enqueue(String key, Future<void> Function() task) {
    if (_pendingKeys.contains(key)) return;
    _pendingKeys.add(key);
    _pending.add((key: key, task: task));
    _pump();
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    while (_pending.isNotEmpty) {
      final next = _pending.removeFirst();
      _pendingKeys.remove(next.key);
      try {
        await next.task();
      } catch (_) {}
    }
    _running = false;
  }
}
