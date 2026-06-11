import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/home_topic_excerpt_provider.dart';

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
