import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/pages/topic_detail_page/controllers/topic_detail_controller.dart';
import 'package:fluxdo/pages/topic_detail_page/topic_detail_page.dart';

void main() {
  test('resolveReadOnscreenPostNumbers only keeps visible read posts', () {
    final readOnscreen = resolveReadOnscreenPostNumbers(
      visiblePostNumbers: {2, 3, 4, 5},
      initialReadPostNumbers: {1, 2, 6},
      sessionReadPostNumbers: {4, 7},
    );

    expect(readOnscreen, {2, 4});
  });

  test('collectChangedPostHtmlForPreload only returns appended posts', () {
    final previousPosts = [
      _post(id: 1, postNumber: 1, cooked: '<p>1</p>'),
      _post(id: 2, postNumber: 2, cooked: '<p>2</p>'),
    ];
    final nextPosts = [
      ...previousPosts,
      _post(id: 3, postNumber: 3, cooked: '<p>3</p>'),
      _post(id: 4, postNumber: 4, cooked: '<p>4</p>'),
    ];

    expect(
      collectChangedPostHtmlForPreload(
        previousPosts: previousPosts,
        nextPosts: nextPosts,
      ),
      ['<p>3</p>', '<p>4</p>'],
    );
  });

  test('collectChangedPostHtmlForPreload only returns prepended posts', () {
    final previousPosts = [
      _post(id: 3, postNumber: 3, cooked: '<p>3</p>'),
      _post(id: 4, postNumber: 4, cooked: '<p>4</p>'),
    ];
    final nextPosts = [
      _post(id: 1, postNumber: 1, cooked: '<p>1</p>'),
      _post(id: 2, postNumber: 2, cooked: '<p>2</p>'),
      ...previousPosts,
    ];

    expect(
      collectChangedPostHtmlForPreload(
        previousPosts: previousPosts,
        nextPosts: nextPosts,
      ),
      ['<p>1</p>', '<p>2</p>'],
    );
  });

  test('collectChangedPostHtmlForPreload falls back to changed html scan', () {
    final previousPosts = [
      _post(id: 1, postNumber: 1, cooked: '<p>旧正文</p>'),
      _post(id: 2, postNumber: 2, cooked: '<p>2</p>'),
    ];
    final nextPosts = [
      _post(id: 1, postNumber: 1, cooked: '<p>新正文</p>'),
      _post(id: 2, postNumber: 2, cooked: '<p>2</p>'),
    ];

    expect(
      collectChangedPostHtmlForPreload(
        previousPosts: previousPosts,
        nextPosts: nextPosts,
      ),
      ['<p>新正文</p>'],
    );
  });
}

Post _post({
  required int id,
  required int postNumber,
  required String cooked,
}) {
  final createdAt = DateTime(2026, 7, 3, 12);
  return Post(
    id: id,
    username: 'tester',
    avatarTemplate: '/avatar/{size}.png',
    cooked: cooked,
    postNumber: postNumber,
    postType: 1,
    updatedAt: createdAt,
    createdAt: createdAt,
    likeCount: 0,
    replyCount: 0,
  );
}
