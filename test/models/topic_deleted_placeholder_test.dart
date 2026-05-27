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

    test('does not filter normal closed topics', () {
      final topic = _topic(closed: true, excerpt: '<p>正常关闭的话题</p>');

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
