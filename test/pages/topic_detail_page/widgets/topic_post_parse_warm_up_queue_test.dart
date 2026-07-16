import 'dart:async';

import 'package:fluxdo/pages/topic_detail_page/widgets/topic_post_parse_warm_up_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const retryDelay = Duration(milliseconds: 400);

  testWidgets('滚动繁忙时不消费队列，空闲后从原位置继续', (tester) async {
    var isBusy = true;
    final scheduled = <FutureOr<void> Function()>[];
    final warmed = <int>[];
    final queue = TopicPostParseWarmUpQueue<int>(
      isBusy: () => isBusy,
      scheduleTask: scheduled.add,
      warmUp: (item, _) => warmed.add(item),
      busyRetryDelay: retryDelay,
    );

    queue.start([1, 2]);
    expect(scheduled, hasLength(1));

    await scheduled.removeAt(0)();
    expect(warmed, isEmpty);
    expect(queue.pendingCount, 2);

    isBusy = false;
    await tester.pump(retryDelay);
    expect(scheduled, hasLength(1));
    await scheduled.removeAt(0)();
    expect(warmed, [1]);
    expect(queue.pendingCount, 1);

    await scheduled.removeAt(0)();
    expect(warmed, [1, 2]);
    expect(queue.pendingCount, 0);
  });

  testWidgets('新一代队列会取消旧队列的延迟恢复', (tester) async {
    var isBusy = true;
    final scheduled = <FutureOr<void> Function()>[];
    final warmed = <int>[];
    final queue = TopicPostParseWarmUpQueue<int>(
      isBusy: () => isBusy,
      scheduleTask: scheduled.add,
      warmUp: (item, _) => warmed.add(item),
      busyRetryDelay: retryDelay,
    );

    queue.start([1]);
    await scheduled.removeAt(0)();
    queue.start([2]);
    expect(scheduled, hasLength(1));

    isBusy = false;
    await tester.pump(retryDelay);
    expect(scheduled, hasLength(1));
    await scheduled.removeAt(0)();

    expect(warmed, [2]);
    expect(queue.pendingCount, 0);
  });

  testWidgets('取消后不会恢复延迟队列', (tester) async {
    final scheduled = <FutureOr<void> Function()>[];
    final warmed = <int>[];
    final queue = TopicPostParseWarmUpQueue<int>(
      isBusy: () => true,
      scheduleTask: scheduled.add,
      warmUp: (item, _) => warmed.add(item),
      busyRetryDelay: retryDelay,
    );

    queue.start([1]);
    await scheduled.removeAt(0)();
    queue.cancel();
    await tester.pump(retryDelay);

    expect(scheduled, isEmpty);
    expect(warmed, isEmpty);
    expect(queue.pendingCount, 0);
  });

  test('单篇预热失败不会阻断后续队列', () async {
    final scheduled = <FutureOr<void> Function()>[];
    final warmed = <int>[];
    final queue = TopicPostParseWarmUpQueue<int>(
      isBusy: () => false,
      scheduleTask: scheduled.add,
      warmUp: (item, _) {
        if (item == 1) throw StateError('parse failed');
        warmed.add(item);
      },
    );

    queue.start([1, 2]);
    await scheduled.removeAt(0)();
    await scheduled.removeAt(0)();

    expect(warmed, [2]);
    expect(queue.pendingCount, 0);
  });

  test('新一代开始后，在途任务可以识别自己已经失效', () async {
    final scheduled = <FutureOr<void> Function()>[];
    final firstWarmUp = Completer<void>();
    bool Function()? firstIsCurrent;
    final warmed = <int>[];
    final queue = TopicPostParseWarmUpQueue<int>(
      isBusy: () => false,
      scheduleTask: scheduled.add,
      warmUp: (item, isCurrent) async {
        if (item == 1) {
          firstIsCurrent = isCurrent;
          await firstWarmUp.future;
          return;
        }
        warmed.add(item);
      },
    );

    queue.start([1]);
    final inFlight = Future<void>.sync(scheduled.removeAt(0));
    await Future<void>.delayed(Duration.zero);
    expect(firstIsCurrent?.call(), isTrue);

    queue.start([2]);
    expect(firstIsCurrent?.call(), isFalse);
    firstWarmUp.complete();
    await inFlight;
    expect(scheduled, hasLength(1));

    await scheduled.removeAt(0)();
    expect(warmed, [2]);
  });
}
