import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';

void main() {
  group('Topic.isDeletedPlaceholder', () {
    test('filters invisible topics', () {
      final topic = _topic(visible: false, closed: true);

      expect(topic.isDeletedPlaceholder, isTrue);
    });

    test('filters author-deleted placeholder excerpt', () {
      final topic = _topic(excerpt: '<p>话题已被作者删除</p>');

      expect(topic.isDeletedPlaceholder, isTrue);
    });

    test('filters author-deleted placeholder variants', () {
      expect(_topic(excerpt: '<p>此话题已被作者删除</p>').isDeletedPlaceholder, isTrue);
      expect(_topic(excerpt: '<p>此内容已被作者删除</p>').isDeletedPlaceholder, isTrue);
      expect(_topic(excerpt: '<p>该主题已经被作者删除</p>').isDeletedPlaceholder, isTrue);
      expect(
        _topic(
          excerpt: '<p>This topic was deleted by the author.</p>',
        ).isDeletedPlaceholder,
        isTrue,
      );
    });

    test('filters deleted metadata from list json', () {
      final topic = Topic.fromJson({
        'id': 42,
        'title': 'Normal topic',
        'slug': 'normal-topic',
        'posts_count': 1,
        'reply_count': 0,
        'views': 0,
        'like_count': 0,
        'category_id': 1,
        'closed': true,
        'deleted_at': '2026-05-29T03:00:00.000Z',
      });

      expect(topic.isDeletedPlaceholder, isTrue);
    });

    test('filters short fancy title placeholder from list json', () {
      final topic = Topic.fromJson({
        'id': 42,
        'title': 'Original title',
        'fancy_title': '<span>此内容已被作者删除</span>',
        'slug': 'normal-topic',
        'posts_count': 1,
        'reply_count': 0,
        'views': 0,
        'like_count': 0,
        'category_id': 1,
        'closed': true,
      });

      expect(topic.isDeletedPlaceholder, isTrue);
    });

    test('does not filter normal closed topics', () {
      final topic = _topic(closed: true, excerpt: '<p>正常关闭的话题</p>');

      expect(topic.isDeletedPlaceholder, isFalse);
    });

    test('does not filter locked topics without deleted signals', () {
      final topic = _topic(closed: true, excerpt: null);

      expect(topic.isDeletedPlaceholder, isFalse);
    });

    test('does not filter long discussions mentioning deleted topics', () {
      final topic = _topic(excerpt: '<p>我想讨论一下为什么有些话题已被作者删除后还会出现在列表里。</p>');

      expect(topic.isDeletedPlaceholder, isFalse);
    });
  });
}

Topic _topic({bool visible = true, bool closed = false, String? excerpt}) {
  return Topic(
    id: 42,
    title: 'Normal topic',
    slug: 'normal-topic',
    postsCount: 1,
    replyCount: 0,
    views: 0,
    likeCount: 0,
    categoryId: '1',
    visible: visible,
    closed: closed,
    excerpt: excerpt,
  );
}
