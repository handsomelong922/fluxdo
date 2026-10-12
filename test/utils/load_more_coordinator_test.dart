import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/load_more_coordinator.dart';

void main() {
  group('LoadMoreCoordinator', () {
    test('忙碌通知抛错仍释放锁，后续请求可以继续', () async {
      final changes = <bool>[];
      var throwOnce = true;
      var loads = 0;
      final coordinator = LoadMoreCoordinator(
        onRunningChanged: (running) {
          changes.add(running);
          if (running && throwOnce) {
            throwOnce = false;
            throw StateError('通知失败');
          }
        },
      );
      Future<void> run() => coordinator.loadMore(
        loadMore: () async {
          loads++;
        },
        hasMore: () => true,
        isActive: () => true,
      );
      await expectLater(run(), throwsStateError);
      expect(coordinator.isRunning, isFalse);
      expect(loads, 0);
      await run();
      expect(loads, 1);
      expect(changes, [true, false, true, false]);
    });
    test('视口预取同时扩大触发与冷却解除边界，默认仍是200', () async {
      final coordinator = LoadMoreCoordinator();
      expect(coordinator.shouldTriggerForDistance(450), isFalse);
      expect(
        coordinator.shouldTriggerForDistance(450, prefetchDistance: 600),
        isTrue,
      );
      await coordinator.loadMore(
        loadMore: () async {},
        hasMore: () => true,
        isActive: () => true,
        progressCount: () => 10,
      );
      expect(coordinator.isCoolingDown, isTrue);
      expect(
        coordinator.shouldTriggerForDistance(450, prefetchDistance: 600),
        isFalse,
      );
      expect(coordinator.isCoolingDown, isTrue);
      expect(
        coordinator.shouldTriggerForDistance(600, prefetchDistance: 600),
        isFalse,
      );
      expect(coordinator.isCoolingDown, isFalse);
      expect(
        coordinator.shouldTriggerForDistance(599, prefetchDistance: 600),
        isTrue,
      );
    });

    test('加载抛错也结束忙碌状态', () async {
      final changes = <bool>[];
      final coordinator = LoadMoreCoordinator(onRunningChanged: changes.add);
      await expectLater(
        coordinator.loadMore(
          loadMore: () async => throw StateError('失败'),
          hasMore: () => true,
          isActive: () => true,
        ),
        throwsStateError,
      );
      expect(changes, [true, false]);
      expect(coordinator.isRunning, isFalse);
    });
    test('默认只触发一次 loadMore', () async {
      final coordinator = LoadMoreCoordinator();
      var calls = 0;
      var count = 10;

      await coordinator.loadMore(
        loadMore: () async {
          calls++;
          count += 10;
        },
        hasMore: () => true,
        isActive: () => true,
        progressCount: () => count,
      );

      expect(calls, 1);
      expect(coordinator.isCoolingDown, isFalse);
    });

    test('仍有更多但没有新增时进入冷却', () async {
      final coordinator = LoadMoreCoordinator();
      var calls = 0;

      await coordinator.loadMore(
        loadMore: () async {
          calls++;
        },
        hasMore: () => true,
        isActive: () => true,
        progressCount: () => 10,
      );

      expect(calls, 1);
      expect(coordinator.isCoolingDown, isTrue);
      expect(coordinator.shouldTriggerForDistance(20), isFalse);
      expect(coordinator.shouldTriggerForDistance(250), isFalse);
      expect(coordinator.isCoolingDown, isFalse);
    });

    test('自定义 auto-continue 策略可连续加载', () async {
      final coordinator = LoadMoreCoordinator();
      var calls = 0;
      var count = 0;

      await coordinator.loadMore(
        loadMore: () async {
          calls++;
          count++;
        },
        hasMore: () => true,
        isActive: () => true,
        progressCount: () => count,
        shouldAutoLoadMore: (attempt) => attempt.attempts < 2,
        shouldCooldown: (attempt) => attempt.hasMore && attempt.attempts >= 2,
      );

      expect(calls, 3);
      expect(coordinator.isCoolingDown, isTrue);
    });
  });

  group('TopicLoadMoreCoordinator', () {
    test('忙碌状态覆盖正则等待和自动续页，重复触发不重复通知', () async {
      final changes = <bool>[];
      final coordinator = TopicLoadMoreCoordinator(
        onRunningChanged: changes.add,
      );
      final filterReady = Completer<int>();
      final reachedFilter = Completer<void>();
      final secondPage = Completer<void>();
      final reachedSecondPage = Completer<void>();
      var calls = 0;
      var reads = 0;
      Future<void> run() => coordinator.loadTopicPage(
        loadMore: () async {
          calls++;
          if (calls == 2) {
            reachedSecondPage.complete();
            await secondPage.future;
          }
        },
        hasMore: () => true,
        isActive: () => true,
        itemCount: () => calls,
        visibleItemCount: () {
          reads++;
          if (reads == 2) {
            reachedFilter.complete();
            return filterReady.future;
          }
          return calls >= 2 ? 7 : calls;
        },
        hasKeywordFilter: true,
      );
      final operation = run();
      await reachedFilter.future;
      expect(changes, [true]);
      expect(coordinator.isRunning, isTrue);
      await run();
      expect(calls, 1);
      expect(changes, [true]);
      filterReady.complete(1);
      await reachedSecondPage.future;
      expect(changes, [true]);
      secondPage.complete();
      await operation;
      expect(changes, [true, false]);
      expect(coordinator.isRunning, isFalse);
    });

    test('最后一次续页已补足可见条目时不误入冷却', () async {
      final coordinator = TopicLoadMoreCoordinator();
      var calls = 0;
      var visible = 0;
      await coordinator.loadTopicPage(
        loadMore: () async {
          calls++;
          visible += calls == 4 ? 5 : 1;
        },
        hasMore: () => true,
        isActive: () => true,
        itemCount: () => calls,
        visibleItemCount: () => visible,
        hasKeywordFilter: true,
      );
      expect(calls, 4);
      expect(coordinator.isCoolingDown, isFalse);
      expect(coordinator.shouldTriggerForDistance(20), isTrue);
    });
    test('空关键词时只触发一次 loadMore', () async {
      final coordinator = TopicLoadMoreCoordinator();
      var calls = 0;
      var count = 10;

      await coordinator.loadTopicPage(
        loadMore: () async {
          calls++;
          count += 10;
        },
        hasMore: () => true,
        isActive: () => true,
        itemCount: () => count,
        hasKeywordFilter: false,
      );

      expect(calls, 1);
      expect(coordinator.isCoolingDown, isFalse);
    });

    test('关键词过滤可见增量不足时最多续载三次', () async {
      final coordinator = TopicLoadMoreCoordinator();
      var calls = 0;
      var visible = 0;

      await coordinator.loadTopicPage(
        loadMore: () async {
          calls++;
          visible++;
        },
        hasMore: () => true,
        isActive: () => true,
        itemCount: () => calls,
        visibleItemCount: () => visible,
        hasKeywordFilter: true,
      );

      expect(calls, 4);
      expect(coordinator.isCoolingDown, isTrue);
    });

    test('等待异步正则计数后才判断续载，匹配失败不加载', () async {
      final coordinator = TopicLoadMoreCoordinator();
      var calls = 0;
      var ready = false;
      await coordinator.loadTopicPage(
        loadMore: () async {
          expect(ready, isTrue);
          calls++;
        },
        hasMore: () => true,
        isActive: () => true,
        itemCount: () => calls,
        visibleItemCount: () async {
          await Future<void>.delayed(Duration.zero);
          ready = true;
          return calls == 0 ? 0 : 5;
        },
        hasKeywordFilter: true,
      );
      expect(calls, 1);
      await coordinator.loadTopicPage(
        loadMore: () async {
          calls++;
        },
        hasMore: () => true,
        isActive: () => true,
        itemCount: () => calls,
        visibleItemCount: () async => -1,
        hasKeywordFilter: true,
      );
      expect(calls, 1);
      expect(coordinator.isRunning, isFalse);
    });

    test('关键词过滤可见增量足够时停止续载', () async {
      final coordinator = TopicLoadMoreCoordinator();
      var calls = 0;
      var visible = 0;

      await coordinator.loadTopicPage(
        loadMore: () async {
          calls++;
          visible += 5;
        },
        hasMore: () => true,
        isActive: () => true,
        itemCount: () => calls,
        visibleItemCount: () => visible,
        hasKeywordFilter: true,
      );

      expect(calls, 1);
      expect(coordinator.isCoolingDown, isFalse);
    });
  });
}
