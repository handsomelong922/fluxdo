import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/post_revision.dart';
import 'package:fluxdo/models/topic.dart';

void main() {
  test('PostRevision parses navigation and body changes', () {
    final revision = PostRevision.fromJson({
      'previous_revision': 2,
      'current_revision': 3,
      'next_revision': 4,
      'last_revision': 5,
      'version_count': 5,
      'username': 'editor',
      'display_username': 'Editor',
      'created_at': '2026-06-18T07:00:00.000Z',
      'edit_reason': 'typo',
      'body_changes': {'inline': '<p><del>old</del><ins>new</ins></p>'},
      'title_changes': ['Old', 'New'],
    });

    expect(revision.currentRevision, 3);
    expect(revision.nextRevision, 4);
    expect(revision.bodyChanges?.inline, contains('ins'));
    expect(revision.titleChanges?.previous, 'Old');
    expect(revision.titleChanges?.current, 'New');
  });

  test('Post parses edit history fields', () {
    final post = Post.fromJson({
      'id': 1,
      'username': 'author',
      'avatar_template': '/avatar/{size}.png',
      'cooked': '<p>Hello</p>',
      'post_number': 1,
      'post_type': 1,
      'created_at': '2026-06-18T07:00:00.000Z',
      'updated_at': '2026-06-18T08:00:00.000Z',
      'like_count': 0,
      'reply_count': 0,
      'version': 3,
      'public_version': 2,
      'can_view_edit_history': true,
      'wiki': true,
      'last_wiki_edit': '2026-06-18T09:00:00.000Z',
      'edit_reason': 'update',
    });

    expect(post.showEditsIndicator, isTrue);
    expect(post.editsCount, 2);
    expect(post.canViewEditHistory, isTrue);
    expect(post.displayDate, post.lastWikiEdit);

    final copied = post.copyWith(version: 4, editReason: 'again');
    expect(copied.editsCount, 3);
    expect(copied.editReason, 'again');
  });
}
