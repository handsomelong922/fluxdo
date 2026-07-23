import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/services/topic_related_topics_loader.dart';

void main() {
  test(
    'deduplicates in-flight requests and caches successful results',
    () async {
      var calls = 0;
      final response = Completer<List<Topic>>();
      final loader = TopicRelatedTopicsLoader(
        fetch: (topicId, postNumber) {
          calls++;
          return response.future;
        },
      );

      final first = loader.load(topicId: 42, postNumber: 9, viewerKey: 'alice');
      final second = loader.load(
        topicId: 42,
        postNumber: 9,
        viewerKey: 'alice',
      );

      expect(identical(first, second), isTrue);
      expect(calls, 1);

      response.complete([_topic(7)]);
      expect((await first).single.id, 7);
      expect(
        (await loader.load(
          topicId: 42,
          postNumber: 9,
          viewerKey: 'alice',
        )).single.id,
        7,
      );
      expect(calls, 1);
    },
  );

  test('separates cache entries by viewer and final post number', () async {
    var calls = 0;
    final loader = TopicRelatedTopicsLoader(
      fetch: (topicId, postNumber) async {
        calls++;
        return [_topic(calls)];
      },
    );

    await loader.load(topicId: 42, postNumber: 9, viewerKey: 'alice');
    await loader.load(topicId: 42, postNumber: 9, viewerKey: 'bob');
    await loader.load(topicId: 42, postNumber: 10, viewerKey: 'alice');

    expect(calls, 3);
  });

  test('does not cache transient failures', () async {
    var calls = 0;
    final loader = TopicRelatedTopicsLoader(
      fetch: (topicId, postNumber) async {
        calls++;
        if (calls == 1) throw StateError('temporary failure');
        return [_topic(7)];
      },
    );

    await expectLater(
      loader.load(topicId: 42, postNumber: 9, viewerKey: 'alice'),
      throwsStateError,
    );
    final recovered = await loader.load(
      topicId: 42,
      postNumber: 9,
      viewerKey: 'alice',
    );

    expect(recovered.single.id, 7);
    expect(calls, 2);
  });

  test('expires old entries and enforces the LRU capacity', () async {
    var now = DateTime(2026, 7, 23, 10);
    var calls = 0;
    final loader = TopicRelatedTopicsLoader(
      cacheTtl: const Duration(minutes: 5),
      maxEntries: 2,
      now: () => now,
      fetch: (topicId, postNumber) async {
        calls++;
        return [_topic(topicId)];
      },
    );

    await loader.load(topicId: 1, postNumber: 1, viewerKey: 'alice');
    await loader.load(topicId: 2, postNumber: 1, viewerKey: 'alice');
    await loader.load(topicId: 1, postNumber: 1, viewerKey: 'alice');
    await loader.load(topicId: 3, postNumber: 1, viewerKey: 'alice');
    await loader.load(topicId: 2, postNumber: 1, viewerKey: 'alice');
    expect(calls, 4);

    now = now.add(const Duration(minutes: 6));
    await loader.load(topicId: 1, postNumber: 1, viewerKey: 'alice');
    expect(calls, 5);
  });
}

Topic _topic(int id) {
  return Topic(
    id: id,
    title: 'topic $id',
    slug: 'topic-$id',
    postsCount: 1,
    replyCount: 0,
    views: 0,
    likeCount: 0,
    categoryId: '1',
  );
}
