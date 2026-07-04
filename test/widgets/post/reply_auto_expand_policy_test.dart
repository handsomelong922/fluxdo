import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/post/reply_auto_expand_policy.dart';

void main() {
  setUp(() async {
    AutoReplyPrefetchQueue.instance.clearPending();
    await AutoReplyPrefetchQueue.instance.debugIdle;
  });

  tearDown(() async {
    AutoReplyPrefetchQueue.instance.clearPending();
    await AutoReplyPrefetchQueue.instance.debugIdle;
  });

  test('cancel removes pending task before execution', () async {
    final queue = AutoReplyPrefetchQueue.instance;
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    var secondRan = false;

    queue.enqueue('first', () async {
      firstStarted.complete();
      await releaseFirst.future;
    });
    queue.enqueue('second', () async {
      secondRan = true;
    });

    await firstStarted.future;
    expect(queue.debugPendingTaskCount, 1);

    queue.cancel('second');
    expect(queue.debugPendingTaskCount, 0);

    releaseFirst.complete();
    await queue.debugIdle;
    expect(secondRan, isFalse);
  });

  test('duplicate key only enqueues once', () async {
    final queue = AutoReplyPrefetchQueue.instance;
    var runCount = 0;

    queue.enqueue('duplicate', () async {
      runCount += 1;
    });
    queue.enqueue('duplicate', () async {
      runCount += 100;
    });

    await queue.debugIdle;
    expect(runCount, 1);
  });
}
