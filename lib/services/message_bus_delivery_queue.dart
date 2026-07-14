part of 'message_bus_service.dart';

/// MessageBus UI 投递队列。协议进度由 service 在入队前推进，
/// 本类只负责把可延迟的订阅回调/广播让开滚动帧。
@visibleForTesting
class MessageBusDeliveryQueue {
  MessageBusDeliveryQueue({
    required bool Function() isBusy,
    required void Function(MessageBusMessage) deliver,
    int maxPending = 300,
    int drainBatchSize = 12,
    Duration busyRetryDelay = const Duration(milliseconds: 250),
    bool scheduleAutomatically = true,
  }) : _isBusy = isBusy,
       _deliver = deliver,
       _maxPending = maxPending,
       _drainBatchSize = drainBatchSize,
       _busyRetryDelay = busyRetryDelay,
       _scheduleAutomatically = scheduleAutomatically,
       assert(maxPending > 0),
       assert(drainBatchSize > 0);

  final bool Function() _isBusy;
  final void Function(MessageBusMessage) _deliver;
  final int _maxPending;
  final int _drainBatchSize;
  final Duration _busyRetryDelay;
  final bool _scheduleAutomatically;
  final ListQueue<MessageBusMessage> _pending = ListQueue();

  Timer? _drainTimer;
  int _generation = 0;

  @visibleForTesting
  int get pendingCount => _pending.length;

  void add(MessageBusMessage message) {
    if (_pending.isEmpty && !_isBusy()) {
      _deliver(message);
      return;
    }

    // 上限只是内存保险丝：极端积压时先投递最旧消息，
    // 再收新消息。即使必须牺牲一帧，也不让新消息越过旧消息。
    if (_pending.length >= _maxPending) {
      _deliver(_pending.removeFirst());
    }
    _pending.addLast(message);
    _scheduleDrain(_busyRetryDelay);
  }

  void _scheduleDrain(Duration delay) {
    if (!_scheduleAutomatically || (_drainTimer?.isActive ?? false)) return;
    final generation = _generation;
    _drainTimer = Timer(delay, () {
      _drainTimer = null;
      if (generation != _generation) return;
      _drainBatch();
    });
  }

  void _drainBatch() {
    if (_pending.isEmpty) return;
    if (_isBusy()) {
      _scheduleDrain(_busyRetryDelay);
      return;
    }

    var delivered = 0;
    while (_pending.isNotEmpty && delivered < _drainBatchSize && !_isBusy()) {
      _deliver(_pending.removeFirst());
      delivered++;
    }

    if (_pending.isNotEmpty) {
      // Timer.zero 把下一批放回事件队列尾部，避免一次性
      // 排空几百条消息再次阻塞 UI isolate。
      _scheduleDrain(Duration.zero);
    }
  }

  @visibleForTesting
  void debugDrainBatch() => _drainBatch();

  void cancelPending() {
    _generation++;
    _drainTimer?.cancel();
    _drainTimer = null;
    _pending.clear();
  }
}
