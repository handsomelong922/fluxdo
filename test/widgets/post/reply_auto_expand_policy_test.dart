import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/post/reply_auto_expand_policy.dart';

void main() {
  group('shouldAutoExpandRepliesNow', () {
    test('allows small reply groups when no interaction gate blocks it', () {
      expect(
        shouldAutoExpandRepliesNow(
          replyCount: autoExpandReplyThreshold,
          autoLoadRepliesPaused: false,
          hideRepliesButton: false,
          useReplyDialog: false,
        ),
        isTrue,
      );
    });

    test(
      'blocks automatic expansion while scrolling or in non-inline modes',
      () {
        expect(
          shouldAutoExpandRepliesNow(
            replyCount: 1,
            autoLoadRepliesPaused: true,
            hideRepliesButton: false,
            useReplyDialog: false,
          ),
          isFalse,
        );
        expect(
          shouldAutoExpandRepliesNow(
            replyCount: 1,
            autoLoadRepliesPaused: false,
            hideRepliesButton: true,
            useReplyDialog: false,
          ),
          isFalse,
        );
        expect(
          shouldAutoExpandRepliesNow(
            replyCount: 1,
            autoLoadRepliesPaused: false,
            hideRepliesButton: false,
            useReplyDialog: true,
          ),
          isFalse,
        );
      },
    );

    test('keeps large reply groups manual', () {
      expect(
        shouldAutoExpandRepliesNow(
          replyCount: autoExpandReplyThreshold + 1,
          autoLoadRepliesPaused: false,
          hideRepliesButton: false,
          useReplyDialog: false,
        ),
        isFalse,
      );
    });
  });

  group('shouldRunNestedAutoWork', () {
    test('allows visible expanded nodes while the list is idle', () {
      expect(
        shouldRunNestedAutoWork(
          expanded: true,
          isVisible: true,
          autoLoadPaused: false,
          atMaxDepth: false,
        ),
        isTrue,
      );
    });

    test('blocks offscreen scrolling collapsed and max-depth nodes', () {
      for (final blocked
          in <
            ({
              bool expanded,
              bool isVisible,
              bool autoLoadPaused,
              bool atMaxDepth,
            })
          >[
            (
              expanded: true,
              isVisible: false,
              autoLoadPaused: false,
              atMaxDepth: false,
            ),
            (
              expanded: true,
              isVisible: true,
              autoLoadPaused: true,
              atMaxDepth: false,
            ),
            (
              expanded: false,
              isVisible: true,
              autoLoadPaused: false,
              atMaxDepth: false,
            ),
            (
              expanded: true,
              isVisible: true,
              autoLoadPaused: false,
              atMaxDepth: true,
            ),
          ]) {
        expect(
          shouldRunNestedAutoWork(
            expanded: blocked.expanded,
            isVisible: blocked.isVisible,
            autoLoadPaused: blocked.autoLoadPaused,
            atMaxDepth: blocked.atMaxDepth,
          ),
          isFalse,
        );
      }
    });
  });

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
