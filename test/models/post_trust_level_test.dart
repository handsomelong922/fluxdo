import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';

void main() {
  test('Post.fromJson parses trust_level', () {
    final post = Post.fromJson(_postJson(trustLevel: 3));

    expect(post.trustLevel, 3);
  });

  test('Post.copyWith keeps and updates trustLevel', () {
    final post = Post.fromJson(_postJson(trustLevel: 2));

    expect(post.copyWith().trustLevel, 2);
    expect(post.copyWith(trustLevel: 4).trustLevel, 4);
  });
}

Map<String, dynamic> _postJson({required int trustLevel}) {
  return {
    'id': 101,
    'topic_id': 42,
    'username': 'account_name',
    'avatar_template': '',
    'cooked': '<p>content</p>',
    'post_number': 1,
    'post_type': 1,
    'updated_at': '2026-07-07T12:00:00.000Z',
    'created_at': '2026-07-07T12:00:00.000Z',
    'like_count': 0,
    'reply_count': 0,
    'trust_level': trustLevel,
  };
}
