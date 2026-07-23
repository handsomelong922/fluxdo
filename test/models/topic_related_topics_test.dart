import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';

void main() {
  group('TopicDetail related_topics parsing', () {
    test('keeps null when the response omits related_topics', () {
      final detail = TopicDetail.fromJson(_topicJson());

      expect(detail.relatedTopics, isNull);
    });

    test('keeps an explicit empty related_topics list', () {
      final detail = TopicDetail.fromJson(
        _topicJson(relatedTopics: const <Map<String, dynamic>>[]),
      );

      expect(detail.relatedTopics, isEmpty);
    });

    test('treats null and malformed related_topics as an empty list', () {
      final nullDetail = TopicDetail.fromJson(_topicJson(relatedTopics: null));
      final malformedDetail = TopicDetail.fromJson(
        _topicJson(relatedTopics: const {'id': 7}),
      );

      expect(nullDetail.relatedTopics, isEmpty);
      expect(malformedDetail.relatedTopics, isEmpty);
    });

    test('skips malformed related topics without failing the topic detail', () {
      final detail = TopicDetail.fromJson(
        _topicJson(
          relatedTopics: [
            {'id': null, 'title': 'Null id'},
            {'title': 'Missing id'},
            {'id': 0, 'title': 'Invalid id'},
            {'id': 8, 'title': '   '},
            {'id': 9, 'title': 'Invalid optional field', 'posts_count': '1'},
            'not a topic',
            _relatedTopicJson(
              id: 7,
              title: 'Related',
              createdAt: '2026-07-01T00:00:00.000Z',
            ),
          ],
        ),
      );

      expect(detail.id, 42);
      expect(detail.postStream.posts.single.cooked, '<p>topic</p>');
      expect(detail.relatedTopics?.map((topic) => topic.id), [7]);
    });

    test('parses related_topics and ignores suggested_topics', () {
      final detail = TopicDetail.fromJson(
        _topicJson(
          relatedTopics: [
            _relatedTopicJson(
              id: 7,
              title: 'Related',
              createdAt: '2026-07-01T00:00:00.000Z',
            ),
          ],
          suggestedTopics: [
            _relatedTopicJson(
              id: 8,
              title: 'Suggested',
              createdAt: '2026-07-02T00:00:00.000Z',
            ),
          ],
        ),
      );

      expect(detail.relatedTopics, hasLength(1));
      expect(detail.relatedTopics!.single.id, 7);
      expect(detail.relatedTopics!.single.title, 'Related');
      expect(
        detail.relatedTopics!.single.createdAt?.toUtc(),
        DateTime.utc(2026, 7, 1),
      );
    });

    test('copyWith preserves old data unless a new list is supplied', () {
      final related = [
        Topic(
          id: 7,
          title: 'Related',
          slug: 'related',
          postsCount: 1,
          replyCount: 0,
          views: 0,
          likeCount: 0,
          categoryId: '1',
        ),
      ];
      final detail = TopicDetail.fromJson(
        _topicJson(),
      ).copyWith(relatedTopics: related);

      expect(detail.copyWith(title: 'Updated').relatedTopics, same(related));
      expect(detail.copyWith(relatedTopics: const []).relatedTopics, isEmpty);
    });

    test('uses highest_post_number and preserves it through copyWith', () {
      final detail = TopicDetail.fromJson(
        _topicJson(postsCount: 3, highestPostNumber: 9),
      );

      expect(detail.highestPostNumber, 9);
      expect(detail.copyWith(title: 'Updated').highestPostNumber, 9);
      expect(detail.copyWith(highestPostNumber: 10).highestPostNumber, 10);
    });

    test('falls back to posts_count when highest_post_number is missing', () {
      final detail = TopicDetail.fromJson(_topicJson(postsCount: 3));

      expect(detail.highestPostNumber, 3);
    });
  });
}

Map<String, dynamic> _topicJson({
  Object? relatedTopics = _missingField,
  List<Map<String, dynamic>>? suggestedTopics,
  int postsCount = 1,
  Object? highestPostNumber = _missingField,
}) {
  final json = <String, dynamic>{
    'id': 42,
    'title': 'Topic',
    'slug': 'topic',
    'posts_count': postsCount,
    'category_id': 1,
    'post_stream': {
      'posts': [
        {
          'id': 101,
          'post_number': 1,
          'username': 'tester',
          'cooked': '<p>topic</p>',
        },
      ],
      'stream': [101],
    },
  };
  if (!identical(relatedTopics, _missingField)) {
    json['related_topics'] = relatedTopics;
  }
  if (suggestedTopics != null) {
    json['suggested_topics'] = suggestedTopics;
  }
  if (!identical(highestPostNumber, _missingField)) {
    json['highest_post_number'] = highestPostNumber;
  }
  return json;
}

const Object _missingField = Object();

Map<String, dynamic> _relatedTopicJson({
  required int id,
  required String title,
  required String createdAt,
}) {
  return {
    'id': id,
    'title': title,
    'slug': 'topic-$id',
    'posts_count': 1,
    'reply_count': 0,
    'views': 0,
    'like_count': 0,
    'category_id': 1,
    'created_at': createdAt,
  };
}
