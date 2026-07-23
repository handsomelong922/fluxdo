import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/home_topic_excerpt_provider.dart';
import 'package:fluxdo/providers/preferences_provider.dart';
import 'package:fluxdo/services/network/request_scheduler_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

TopicDetail _previewDetail(int topicId, {String? html}) {
  final cooked = html ?? '<p>topic $topicId</p>';
  return TopicDetail(
    id: topicId,
    title: 'topic $topicId',
    slug: 'topic-$topicId',
    postsCount: 3,
    postStream: PostStream(
      posts: [
        Post(
          id: topicId * 10 + 1,
          topicId: topicId,
          username: 'tester',
          avatarTemplate: '/user_avatar/example/{size}/1.png',
          cooked: cooked,
          postNumber: 1,
          postType: 1,
          updatedAt: DateTime(2026, 1, 1),
          createdAt: DateTime(2026, 1, 1),
          likeCount: 0,
          replyCount: 2,
        ),
      ],
      stream: [topicId * 10 + 1],
      gaps: const PostStreamGaps(),
    ),
    categoryId: 1,
    closed: false,
    archived: false,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  tearDown(() {
    RequestSchedulerConfig.maxConcurrent = 3;
    RequestSchedulerConfig.maxPerWindow = 6;
    RequestSchedulerConfig.windowSeconds = 3;
    RequestSchedulerConfig.minIntervalMs = 250;
    RequestSchedulerConfig.resetServerCooldownForTesting();
  });

  test(
    'HomeTopicExcerptLoader deduplicates concurrent requests and caches',
    () async {
      var calls = 0;
      final loader = HomeTopicExcerptLoader(
        minRequestInterval: Duration.zero,
        fetchPreview: (topicId) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          return _previewDetail(topicId);
        },
      );
      addTearDown(loader.dispose);

      final results = await Future.wait([loader.load(42), loader.load(42)]);

      expect(results, ['<p>topic 42</p>', '<p>topic 42</p>']);
      expect(calls, 1);

      expect(await loader.load(42), '<p>topic 42</p>');
      expect(calls, 1);
    },
  );

  test('HomeTopicExcerptLoader cools down failed requests', () async {
    var calls = 0;
    final loader = HomeTopicExcerptLoader(
      minRequestInterval: Duration.zero,
      failureCooldown: const Duration(minutes: 1),
      fetchPreview: (_) async {
        calls++;
        throw StateError('rate limited');
      },
    );
    addTearDown(loader.dispose);

    expect(await loader.load(7), isNull);
    expect(await loader.load(7), isNull);
    expect(calls, 1);
  });

  test(
    'HomeTopicExcerptPauseController keeps loader paused until all tokens release',
    () async {
      var calls = 0;
      final loader = HomeTopicExcerptLoader(
        minRequestInterval: Duration.zero,
        fetchPreview: (topicId) async {
          calls++;
          return _previewDetail(topicId);
        },
      );
      final container = ProviderContainer(
        overrides: [homeTopicExcerptLoaderProvider.overrideWithValue(loader)],
      );
      addTearDown(loader.dispose);
      addTearDown(container.dispose);

      final controller = container.read(
        homeTopicExcerptPauseControllerProvider,
      );
      final tokenA = Object();
      final tokenB = Object();

      controller.acquire(tokenA);
      controller.acquire(tokenB);
      expect(controller.isPaused, isTrue);
      expect(controller.activeTokenCount, 2);
      expect(container.read(homeTopicExcerptPausedProvider), isTrue);

      final pending = loader.load(21);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, 0);

      controller.release(tokenA);
      expect(controller.isPaused, isTrue);
      expect(container.read(homeTopicExcerptPausedProvider), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, 0);

      controller.release(tokenB);
      expect(controller.isPaused, isFalse);
      expect(container.read(homeTopicExcerptPausedProvider), isFalse);
      expect(await pending, '<p>topic 21</p>');
      expect(calls, 1);
    },
  );

  test(
    'runWhilePaused acquires before the action and releases in finally',
    () async {
      final loader = HomeTopicExcerptLoader(
        minRequestInterval: Duration.zero,
        fetchPreview: (topicId) async => _previewDetail(topicId),
      );
      final container = ProviderContainer(
        overrides: [homeTopicExcerptLoaderProvider.overrideWithValue(loader)],
      );
      addTearDown(loader.dispose);
      addTearDown(container.dispose);
      final controller = container.read(
        homeTopicExcerptPauseControllerProvider,
      );
      final release = Completer<void>();

      final result = controller.runWhilePaused<int>(Object(), () async {
        expect(controller.isPaused, isTrue);
        expect(container.read(homeTopicExcerptPausedProvider), isTrue);
        await release.future;
        return 7;
      });

      await Future<void>.delayed(Duration.zero);
      expect(controller.isPaused, isTrue);
      release.complete();
      expect(await result, 7);
      expect(controller.isPaused, isFalse);
      expect(container.read(homeTopicExcerptPausedProvider), isFalse);

      await expectLater(
        controller.runWhilePaused<void>(Object(), () async {
          throw StateError('route failed');
        }),
        throwsStateError,
      );
      expect(controller.isPaused, isFalse);
    },
  );

  test('HomeTopicExcerptLoader spaces queued requests', () async {
    final starts = <DateTime>[];
    final loader = HomeTopicExcerptLoader(
      maxConcurrentRequests: 2,
      minRequestInterval: const Duration(milliseconds: 20),
      fetchPreview: (topicId) async {
        starts.add(DateTime.now());
        return _previewDetail(topicId);
      },
    );
    addTearDown(loader.dispose);

    await Future.wait([loader.load(1), loader.load(2)]);

    expect(starts, hasLength(2));
    expect(
      starts[1].difference(starts[0]).inMilliseconds,
      greaterThanOrEqualTo(15),
    );
  });

  test('HomeTopicExcerptLoader starts a small batch concurrently', () async {
    final release = Completer<void>();
    final firstBatchStarted = Completer<void>();
    final starts = <int>[];
    final loader = HomeTopicExcerptLoader(
      maxConcurrentRequests: 3,
      minRequestInterval: Duration.zero,
      fetchPreview: (topicId) async {
        starts.add(topicId);
        if (starts.length == 3 && !firstBatchStarted.isCompleted) {
          firstBatchStarted.complete();
        }
        await release.future;
        return _previewDetail(topicId);
      },
    );
    addTearDown(loader.dispose);

    final futures = [loader.load(1), loader.load(2), loader.load(3)];

    await firstBatchStarted.future.timeout(const Duration(milliseconds: 100));
    expect(starts, unorderedEquals([1, 2, 3]));

    release.complete();
    await Future.wait(futures);
  });

  test('HomeTopicExcerptLoader limits active requests to batch size', () async {
    var active = 0;
    var maxActive = 0;
    final loader = HomeTopicExcerptLoader(
      maxConcurrentRequests: 2,
      minRequestInterval: Duration.zero,
      fetchPreview: (topicId) async {
        active++;
        if (active > maxActive) maxActive = active;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active--;
        return _previewDetail(topicId);
      },
    );
    addTearDown(loader.dispose);

    await Future.wait([loader.load(1), loader.load(2), loader.load(3)]);

    expect(maxActive, 2);
  });

  test(
    'HomeTopicExcerptLoader releases queued topics without fetching',
    () async {
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final fetchedTopicIds = <int>[];
      final loader = HomeTopicExcerptLoader(
        maxConcurrentRequests: 1,
        minRequestInterval: Duration.zero,
        fetchPreview: (topicId) async {
          fetchedTopicIds.add(topicId);
          if (topicId == 1 && !firstStarted.isCompleted) {
            firstStarted.complete();
            await releaseFirst.future;
          }
          return _previewDetail(topicId);
        },
      );
      addTearDown(loader.dispose);

      final first = loader.load(1);
      final second = loader.load(2);

      await firstStarted.future.timeout(const Duration(milliseconds: 100));
      loader.release(2);
      releaseFirst.complete();

      expect(await first, '<p>topic 1</p>');
      expect(await second, isNull);
      expect(fetchedTopicIds, [1]);
    },
  );

  test('home excerpt batch size reserves a foreground request slot', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final notifier = PreferencesNotifier(prefs);

    await notifier.setMaxConcurrent(3);
    await notifier.setHomeExcerptBatchSize(8);

    expect(resolveHomeExcerptBatchSize(notifier.state), 2);

    await notifier.setMaxConcurrent(1);

    expect(resolveHomeExcerptBatchSize(notifier.state), 1);
  });

  test(
    'HomeTopicExcerptLoader exposes cached excerpts synchronously',
    () async {
      final loader = HomeTopicExcerptLoader(
        minRequestInterval: Duration.zero,
        fetchPreview: (topicId) async => _previewDetail(topicId),
      );
      addTearDown(loader.dispose);

      expect(await loader.load(11), '<p>topic 11</p>');

      expect(loader.peekCached(11), '<p>topic 11</p>');
      expect(loader.peekCachedPreview(11)?.title, 'topic 11');
    },
  );

  test(
    'HomeTopicExcerptLoader keeps preview cache smaller than excerpt cache',
    () async {
      final loader = HomeTopicExcerptLoader(
        minRequestInterval: Duration.zero,
        maxCacheEntries: 4,
        maxPreviewEntries: 2,
        fetchPreview: (topicId) async => _previewDetail(topicId),
      );
      addTearDown(loader.dispose);

      await loader.load(1);
      await loader.load(2);
      await loader.load(3);

      expect(loader.peekCached(1), isNotNull);
      expect(loader.peekCached(2), isNotNull);
      expect(loader.peekCached(3), isNotNull);
      expect(loader.peekCachedPreview(1), isNull);
      expect(loader.peekCachedPreview(2)?.id, 2);
      expect(loader.peekCachedPreview(3)?.id, 3);
    },
  );

  test(
    'HomeTopicExcerptLoader warmupTopics dedupes ids and respects maxTopics',
    () async {
      final warmedIds = <int>[];
      final loader = HomeTopicExcerptLoader(
        minRequestInterval: Duration.zero,
        fetchPreview: (topicId) async {
          warmedIds.add(topicId);
          return _previewDetail(topicId);
        },
      );
      addTearDown(loader.dispose);

      final warmed = await loader.warmupTopics([1, 2, 2, 3, 4], maxTopics: 3);

      expect(warmed, 3);
      expect(warmedIds, unorderedEquals([1, 2, 3]));
    },
  );

  test(
    'resolveBestTopicExcerptHtml prefers cached html and falls back to topic excerpt',
    () {
      final topic = Topic(
        id: 1,
        title: 'Hello',
        slug: 'hello',
        postsCount: 1,
        replyCount: 0,
        views: 0,
        likeCount: 0,
        categoryId: '1',
        excerpt: '<p>excerpt</p>',
      );

      expect(
        resolveBestTopicExcerptHtml(topic, cachedHtml: '<p>cached</p>'),
        '<p>cached</p>',
      );
      expect(resolveBestTopicExcerptHtml(topic), '<p>excerpt</p>');
    },
  );

  test(
    'HomeTopicExcerptLoader reuses persistent cache after recreation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var calls = 0;

      final firstLoader = HomeTopicExcerptLoader(
        minRequestInterval: Duration.zero,
        persistentCache: HomeTopicExcerptPersistentCache(
          prefs,
          persistDebounce: Duration.zero,
        ),
        fetchPreview: (topicId) async {
          calls++;
          return _previewDetail(topicId);
        },
      );

      expect(await firstLoader.load(42), '<p>topic 42</p>');
      await Future<void>.delayed(Duration.zero);
      firstLoader.dispose();

      final secondLoader = HomeTopicExcerptLoader(
        minRequestInterval: Duration.zero,
        persistentCache: HomeTopicExcerptPersistentCache(
          prefs,
          persistDebounce: Duration.zero,
        ),
        fetchPreview: (_) async {
          calls++;
          throw StateError('should not fetch when persistent cache is valid');
        },
      );
      addTearDown(secondLoader.dispose);

      expect(await secondLoader.load(42), '<p>topic 42</p>');
      expect(calls, 1);
    },
  );

  test('HomeTopicExcerptPersistentCache drops expired entries', () async {
    final oldCachedAt = DateTime.now()
        .subtract(const Duration(days: 2))
        .millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      HomeTopicExcerptPersistentCache.storageKey: jsonEncode({
        '42': {'excerpt': '<p>old</p>', 'cachedAt': oldCachedAt},
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final cache = HomeTopicExcerptPersistentCache(
      prefs,
      persistDebounce: Duration.zero,
    );

    expect(cache.read(42, const Duration(days: 1)), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(prefs.getString(HomeTopicExcerptPersistentCache.storageKey), isNull);
  });

  test('HomeTopicExcerptLoader times out stalled requests', () async {
    final loader = HomeTopicExcerptLoader(
      minRequestInterval: Duration.zero,
      failureCooldown: const Duration(minutes: 1),
      requestTimeout: const Duration(milliseconds: 5),
      fetchPreview: (_) => Completer<TopicDetail?>().future,
    );
    addTearDown(loader.dispose);

    expect(await loader.load(9), isNull);
  });

  test(
    'homeTopicExcerptProvider auto-disposes after listeners leave',
    () async {
      final loader = HomeTopicExcerptLoader(
        minRequestInterval: Duration.zero,
        fetchPreview: (topicId) async => _previewDetail(topicId),
      );
      final container = ProviderContainer(
        overrides: [homeTopicExcerptLoaderProvider.overrideWithValue(loader)],
      );
      addTearDown(loader.dispose);
      addTearDown(container.dispose);

      final sub = container.listen<AsyncValue<String?>>(
        homeTopicExcerptProvider(99),
        (_, _) {},
        fireImmediately: true,
      );

      await _waitUntil(
        () =>
            container.read(homeTopicExcerptProvider(99)).value ==
            '<p>topic 99</p>',
      );
      expect(container.exists(homeTopicExcerptProvider(99)), isTrue);

      sub.close();
      await container.pump();

      expect(container.exists(homeTopicExcerptProvider(99)), isFalse);
    },
  );
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('condition was not met within $timeout');
}
