import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/home_topic_excerpt_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'HomeTopicExcerptLoader deduplicates concurrent requests and caches',
    () async {
      var calls = 0;
      final loader = HomeTopicExcerptLoader(
        minRequestInterval: Duration.zero,
        fetchExcerpt: (topicId) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          return '<p>topic $topicId</p>';
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
      fetchExcerpt: (_) async {
        calls++;
        throw StateError('rate limited');
      },
    );
    addTearDown(loader.dispose);

    expect(await loader.load(7), isNull);
    expect(await loader.load(7), isNull);
    expect(calls, 1);
  });

  test('HomeTopicExcerptLoader spaces queued requests', () async {
    final starts = <DateTime>[];
    final loader = HomeTopicExcerptLoader(
      maxConcurrentRequests: 2,
      minRequestInterval: const Duration(milliseconds: 20),
      fetchExcerpt: (topicId) async {
        starts.add(DateTime.now());
        return '<p>topic $topicId</p>';
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
      fetchExcerpt: (topicId) async {
        starts.add(topicId);
        if (starts.length == 3 && !firstBatchStarted.isCompleted) {
          firstBatchStarted.complete();
        }
        await release.future;
        return '<p>topic $topicId</p>';
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
      fetchExcerpt: (topicId) async {
        active++;
        if (active > maxActive) maxActive = active;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active--;
        return '<p>topic $topicId</p>';
      },
    );
    addTearDown(loader.dispose);

    await Future.wait([loader.load(1), loader.load(2), loader.load(3)]);

    expect(maxActive, 2);
  });

  test(
    'HomeTopicExcerptLoader waits while paused and resumes queued work',
    () async {
      var calls = 0;
      final loader = HomeTopicExcerptLoader(
        minRequestInterval: Duration.zero,
        fetchExcerpt: (topicId) async {
          calls++;
          return '<p>topic $topicId</p>';
        },
      );
      addTearDown(loader.dispose);

      loader.setPaused(true);
      final future = loader.load(11);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(calls, 0);

      loader.setPaused(false);

      expect(await future, '<p>topic 11</p>');
      expect(calls, 1);
    },
  );

  test(
    'HomeTopicExcerptLoader keeps cached excerpts visible while paused',
    () async {
      final loader = HomeTopicExcerptLoader(
        minRequestInterval: Duration.zero,
        fetchExcerpt: (topicId) async => '<p>topic $topicId</p>',
      );
      addTearDown(loader.dispose);

      expect(await loader.load(11), '<p>topic 11</p>');

      loader.setPaused(true);

      expect(loader.peekCached(11), '<p>topic 11</p>');
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
        persistentCache: HomeTopicExcerptPersistentCache(prefs),
        fetchExcerpt: (topicId) async {
          calls++;
          return '<p>topic $topicId</p>';
        },
      );

      expect(await firstLoader.load(42), '<p>topic 42</p>');
      await Future<void>.delayed(Duration.zero);
      firstLoader.dispose();

      final secondLoader = HomeTopicExcerptLoader(
        minRequestInterval: Duration.zero,
        persistentCache: HomeTopicExcerptPersistentCache(prefs),
        fetchExcerpt: (_) async {
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
    final cache = HomeTopicExcerptPersistentCache(prefs);

    expect(cache.read(42, const Duration(days: 1)), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(prefs.getString(HomeTopicExcerptPersistentCache.storageKey), isNull);
  });

  test('HomeTopicExcerptLoader times out stalled requests', () async {
    final loader = HomeTopicExcerptLoader(
      minRequestInterval: Duration.zero,
      failureCooldown: const Duration(minutes: 1),
      requestTimeout: const Duration(milliseconds: 5),
      fetchExcerpt: (_) => Completer<String?>().future,
    );
    addTearDown(loader.dispose);

    expect(await loader.load(9), isNull);
  });
}
