import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/message_bus_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MessageBusMessage message(int id) => MessageBusMessage(
    channel: '/latest',
    messageId: id,
    data: const <String, dynamic>{},
  );

  test('defers while busy and drains in bounded FIFO batches', () {
    var busy = true;
    final delivered = <int>[];
    final queue = MessageBusDeliveryQueue(
      isBusy: () => busy,
      deliver: (value) => delivered.add(value.messageId),
      drainBatchSize: 2,
      scheduleAutomatically: false,
    );

    for (var id = 1; id <= 5; id++) {
      queue.add(message(id));
    }
    expect(delivered, isEmpty);
    expect(queue.pendingCount, 5);

    busy = false;
    queue.debugDrainBatch();
    expect(delivered, [1, 2]);
    expect(queue.pendingCount, 3);
    queue.debugDrainBatch();
    expect(delivered, [1, 2, 3, 4]);
    queue.debugDrainBatch();
    expect(delivered, [1, 2, 3, 4, 5]);
  });

  test('full queue preserves order instead of letting new messages jump', () {
    var busy = true;
    final delivered = <int>[];
    final queue = MessageBusDeliveryQueue(
      isBusy: () => busy,
      deliver: (value) => delivered.add(value.messageId),
      maxPending: 2,
      scheduleAutomatically: false,
    );

    queue.add(message(1));
    queue.add(message(2));
    queue.add(message(3));
    expect(delivered, [1]);
    expect(queue.pendingCount, 2);

    busy = false;
    queue.debugDrainBatch();
    expect(delivered, [1, 2, 3]);
  });

  test('cancelPending drops old-session callbacks', () {
    var busy = true;
    final delivered = <int>[];
    final queue = MessageBusDeliveryQueue(
      isBusy: () => busy,
      deliver: (value) => delivered.add(value.messageId),
      scheduleAutomatically: false,
    );

    queue.add(message(1));
    queue.add(message(2));
    queue.cancelPending();
    busy = false;
    queue.debugDrainBatch();

    expect(delivered, isEmpty);
    expect(queue.pendingCount, 0);
  });

  test('idle delivery stays synchronous when no backlog exists', () {
    final delivered = <int>[];
    final queue = MessageBusDeliveryQueue(
      isBusy: () => false,
      deliver: (value) => delivered.add(value.messageId),
      scheduleAutomatically: false,
    );

    queue.add(message(7));
    expect(delivered, [7]);
    expect(queue.pendingCount, 0);
  });
}
