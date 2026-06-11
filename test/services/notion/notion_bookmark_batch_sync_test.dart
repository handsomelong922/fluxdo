import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/services/notion/notion_bookmark_batch_sync.dart';
import 'package:fluxdo/services/notion/notion_config.dart';
import 'package:fluxdo/services/notion/notion_sync_service.dart';

void main() {
  test('按收藏时间顺序预查重后再同步未存在的历史书签', () async {
    final config = _config();
    final older = _bookmark(
      id: 1,
      title: 'older',
      bookmarkId: 11,
      bookmarkCreatedAt: DateTime.utc(2026, 6, 1),
    );
    final duplicate = _bookmark(
      id: 2,
      title: 'duplicate',
      bookmarkId: 12,
      bookmarkCreatedAt: DateTime.utc(2026, 6, 2),
    );
    final newer = _bookmark(
      id: 3,
      title: 'newer',
      bookmarkId: 13,
      bookmarkCreatedAt: DateTime.utc(2026, 6, 3),
    );
    final events = <String>[];

    final sync = NotionBookmarkBatchSync(
      config: config,
      notionSyncService: _NoopNotionSyncService(config),
      fetchBookmarkPage: (_) async =>
          TopicListResponse(topics: [newer, duplicate, older]),
      isAlreadySynced: (bookmark) async {
        events.add('check:${bookmark.title}');
        return bookmark.id == duplicate.id;
      },
      syncBookmark: (bookmark) async {
        events.add('sync:${bookmark.title}');
        return NotionSyncResult(
          pageId: 'page-${bookmark.id}',
          pageUrl: 'https://notion.so/page-${bookmark.id}',
          postCount: 1,
          duplicated: false,
        );
      },
    );

    final result = await sync.syncAll();

    expect(result.total, 3);
    expect(result.success, 2);
    expect(result.skipped, 1);
    expect(result.failed, 0);
    expect(events, [
      'check:older',
      'sync:older',
      'check:duplicate',
      'check:newer',
      'sync:newer',
    ]);
  });

  test('书签列表解析保留收藏创建时间', () {
    final response = TopicListResponse.fromJson({
      'user_bookmark_list': {
        'bookmarks': [
          {
            'id': 101,
            'topic_id': 42,
            'title': '收藏',
            'slug': 'bookmark',
            'created_at': '2026-06-09T08:30:00.000Z',
            'highest_post_number': 1,
            'bookmarkable_type': 'Topic',
            'user': {
              'id': 7,
              'username': 'alice',
              'avatar_template': '/user_avatar/linux.do/alice/{size}/1_2.png',
            },
          },
        ],
      },
    });

    expect(response.topics.single.bookmarkId, 101);
    expect(
      response.topics.single.bookmarkCreatedAt?.toUtc(),
      DateTime.utc(2026, 6, 9, 8, 30),
    );
  });
}

NotionConfig _config() {
  return const NotionConfig(
    integrationToken: 'secret_test',
    databaseId: 'database_test',
  );
}

Topic _bookmark({
  required int id,
  required String title,
  required int bookmarkId,
  required DateTime bookmarkCreatedAt,
}) {
  return Topic(
    id: id,
    title: title,
    slug: title,
    postsCount: 1,
    replyCount: 0,
    views: 0,
    likeCount: 0,
    categoryId: '1',
    bookmarkId: bookmarkId,
    bookmarkableType: 'Topic',
    bookmarkCreatedAt: bookmarkCreatedAt,
  );
}

class _NoopNotionSyncService extends NotionSyncService {
  _NoopNotionSyncService(NotionConfig config) : super(config: config);

  @override
  Future<void> ensureDatabaseReadyForSync() async {}
}
