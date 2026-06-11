import 'package:flutter/foundation.dart';

import '../../models/topic.dart';
import '../discourse/discourse_service.dart';
import 'notion_config.dart';
import 'notion_sync_service.dart';

typedef NotionBookmarkPageFetcher =
    Future<TopicListResponse> Function(int page);
typedef NotionBookmarkDuplicateChecker = Future<bool> Function(Topic bookmark);
typedef NotionBookmarkSyncExecutor =
    Future<NotionSyncResult> Function(Topic bookmark);

enum NotionBookmarkBatchPhase { fetchBookmarks, syncItem, done }

class NotionBookmarkBatchProgress {
  const NotionBookmarkBatchProgress({
    required this.phase,
    this.current = 0,
    this.total = 0,
    this.title,
  });

  final NotionBookmarkBatchPhase phase;
  final int current;
  final int total;
  final String? title;
}

class NotionBookmarkBatchResult {
  const NotionBookmarkBatchResult({
    required this.total,
    required this.success,
    required this.skipped,
    required this.failed,
  });

  final int total;
  final int success;
  final int skipped;
  final int failed;
}

class NotionBookmarkBatchSync {
  NotionBookmarkBatchSync({
    required this.config,
    DiscourseService? discourseService,
    NotionSyncService? notionSyncService,
    NotionBookmarkPageFetcher? fetchBookmarkPage,
    NotionBookmarkDuplicateChecker? isAlreadySynced,
    NotionBookmarkSyncExecutor? syncBookmark,
  }) : _discourseService = discourseService ?? DiscourseService(),
       _notionSyncService =
           notionSyncService ?? NotionSyncService(config: config),
       _fetchBookmarkPage = fetchBookmarkPage,
       _isAlreadySynced = isAlreadySynced,
       _syncBookmark = syncBookmark;

  static const int _maxBookmarkPages = 100;

  final NotionConfig config;
  final DiscourseService _discourseService;
  final NotionSyncService _notionSyncService;
  final NotionBookmarkPageFetcher? _fetchBookmarkPage;
  final NotionBookmarkDuplicateChecker? _isAlreadySynced;
  final NotionBookmarkSyncExecutor? _syncBookmark;

  Future<NotionBookmarkBatchResult> syncAll({
    void Function(NotionBookmarkBatchProgress progress)? onProgress,
  }) async {
    final bookmarks = await _fetchAllBookmarks(onProgress: onProgress);
    if (bookmarks.isEmpty) {
      onProgress?.call(
        const NotionBookmarkBatchProgress(phase: NotionBookmarkBatchPhase.done),
      );
      return const NotionBookmarkBatchResult(
        total: 0,
        success: 0,
        skipped: 0,
        failed: 0,
      );
    }
    bookmarks.sort(_compareByBookmarkCreatedAt);
    await _notionSyncService.ensureDatabaseReadyForSync();

    var success = 0;
    var skipped = 0;
    var failed = 0;

    for (var i = 0; i < bookmarks.length; i++) {
      final bookmark = bookmarks[i];
      onProgress?.call(
        NotionBookmarkBatchProgress(
          phase: NotionBookmarkBatchPhase.syncItem,
          current: i + 1,
          total: bookmarks.length,
          title: bookmark.title,
        ),
      );

      try {
        if (await _bookmarkExistsInNotion(bookmark)) {
          skipped++;
          continue;
        }
        final result = await _syncSingleBookmark(bookmark);
        if (result.duplicated) {
          skipped++;
        } else {
          success++;
        }
      } catch (error, stackTrace) {
        failed++;
        debugPrint(
          '[NotionBookmarkBatchSync] bookmark ${bookmark.id} failed: '
          '$error\n$stackTrace',
        );
      }
    }

    onProgress?.call(
      NotionBookmarkBatchProgress(
        phase: NotionBookmarkBatchPhase.done,
        current: bookmarks.length,
        total: bookmarks.length,
      ),
    );
    return NotionBookmarkBatchResult(
      total: bookmarks.length,
      success: success,
      skipped: skipped,
      failed: failed,
    );
  }

  Future<List<Topic>> _fetchAllBookmarks({
    void Function(NotionBookmarkBatchProgress progress)? onProgress,
  }) async {
    final bookmarks = <Topic>[];
    var page = 0;

    while (page < _maxBookmarkPages) {
      onProgress?.call(
        NotionBookmarkBatchProgress(
          phase: NotionBookmarkBatchPhase.fetchBookmarks,
          current: page + 1,
        ),
      );
      final fetcher = _fetchBookmarkPage;
      final response = fetcher != null
          ? await fetcher(page)
          : await _discourseService.getUserBookmarks(
              page: page,
              background: true,
            );
      bookmarks.addAll(response.topics);
      if (response.moreTopicsUrl == null || response.topics.isEmpty) break;
      page++;
    }

    return bookmarks;
  }

  int _compareByBookmarkCreatedAt(Topic a, Topic b) {
    final aTime = a.bookmarkCreatedAt ?? a.createdAt;
    final bTime = b.bookmarkCreatedAt ?? b.createdAt;
    if (aTime != null && bTime != null) {
      final byTime = aTime.compareTo(bTime);
      if (byTime != 0) return byTime;
    } else if (aTime != null) {
      return -1;
    } else if (bTime != null) {
      return 1;
    }
    return (a.bookmarkId ?? 0).compareTo(b.bookmarkId ?? 0);
  }

  Future<bool> _bookmarkExistsInNotion(Topic bookmark) {
    final checker = _isAlreadySynced;
    if (checker != null) return checker(bookmark);
    return _notionSyncService.isBookmarkAlreadySynced(bookmark);
  }

  Future<NotionSyncResult> _syncSingleBookmark(Topic bookmark) async {
    final sync = _syncBookmark;
    if (sync != null) return sync(bookmark);

    final detail = await _discourseService.getTopicDetail(
      bookmark.id,
      background: true,
    );
    if (_isPostBookmark(bookmark)) {
      final post = await _discourseService.getPostByNumber(
        bookmark.id,
        bookmark.bookmarkedPostNumber!,
        background: true,
      );
      return _notionSyncService.syncPost(
        detail: detail,
        post: post,
        onDuplicate: DuplicateAction.skip,
        source: NotionSyncSource.bookmark,
        bookmark: bookmark,
        background: true,
      );
    }

    return _notionSyncService.syncTopic(
      detail: detail,
      scope: config.syncScope,
      onDuplicate: DuplicateAction.skip,
      source: NotionSyncSource.bookmark,
      bookmark: bookmark,
      background: true,
    );
  }

  bool _isPostBookmark(Topic bookmark) {
    return bookmark.bookmarkableType == 'Post' &&
        bookmark.bookmarkedPostNumber != null;
  }
}
