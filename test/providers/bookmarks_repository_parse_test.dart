import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/bookmarks_repository.dart';

Map<String, dynamic> _bookmark(int id, Object? updatedAt) => {
  'id': id,
  'topic_id': id + 100,
  'title': '书签 $id',
  'updated_at': updatedAt,
};

void main() {
  test('缺失书签列表不是完整空页，显式空列表才是', () {
    expect(parseBookmarkPage({}).isComplete, isFalse);
    expect(parseBookmarkPage({'user_bookmark_list': {}}).isComplete, isFalse);
    expect(
      parseBookmarkPage({
        'user_bookmark_list': {'bookmarks': null},
      }).isComplete,
      isFalse,
    );
    expect(
      parseBookmarkPage({
        'user_bookmark_list': {'bookmarks': []},
      }).isComplete,
      isTrue,
    );
  });

  test('动态键类型的书签容器保留有效条目和分页信息', () {
    final result = parseBookmarkPage({
      'user_bookmark_list': <dynamic, dynamic>{
        'bookmarks': [_bookmark(7, '2026-10-15T00:10:10Z')],
        'more_bookmarks_url': '/u/test/bookmarks.json?page=1',
      },
    });

    expect(result.isComplete, isTrue);
    expect(result.topics.map((topic) => topic.id), [107]);
    expect(result.entries.map((entry) => entry.bookmarkId), [7]);
    expect(result.moreUrl, '/u/test/bookmarks.json?page=1');
  });

  test('非 Map 书签容器不是完整空页', () {
    for (final container in [null, [], 'invalid', 1]) {
      final result = parseBookmarkPage({'user_bookmark_list': container});
      expect(result.isComplete, isFalse);
      expect(result.topics, isEmpty);
      expect(result.entries, isEmpty);
      expect(result.moreUrl, isNull);
    }
  });

  test('异常更新时间仅跳过缓存，不丢失整页书签或分页信息', () {
    final result = parseBookmarkPage({
      'user_bookmark_list': {
        'bookmarks': [
          _bookmark(1, 'not a date'),
          _bookmark(2, null),
          _bookmark(3, ''),
          _bookmark(4, 123),
          _bookmark(5, '2026-10-15T08:09:10+08:00'),
          _bookmark(6, '2026-10-15T00:10:10Z'),
        ],
        'more_bookmarks_url': '/u/test/bookmarks.json?page=1',
      },
    });

    expect(result.topics.map((topic) => topic.id), [
      101,
      102,
      103,
      104,
      105,
      106,
    ]);
    expect(result.isComplete, isFalse);
    expect(result.entries.map((entry) => entry.bookmarkId), [5, 6]);
    expect(
      result.entries.first.updatedAt.toUtc(),
      DateTime.utc(2026, 10, 15, 0, 9, 10),
    );
    expect(result.entries.first.updatedAt.isUtc, isFalse);
    expect(result.moreUrl, '/u/test/bookmarks.json?page=1');
  });
}
