import 'package:flutter/foundation.dart';

import '../../models/topic.dart';
import '../discourse/discourse_service.dart';
import 'notion_config.dart';
import 'notion_sync_service.dart';

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
  }) : _discourseService = discourseService ?? DiscourseService(),
       _notionSyncService =
           notionSyncService ?? NotionSyncService(config: config);

  static const int _maxBookmarkPages = 100;

  final NotionConfig config;
  final DiscourseService _discourseService;
  final NotionSyncService _notionSyncService;

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
        final result = await _syncBookmark(bookmark);
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
      final response = await _discourseService.getUserBookmarks(page: page);
      bookmarks.addAll(response.topics);
      if (response.moreTopicsUrl == null || response.topics.isEmpty) break;
      page++;
    }

    return bookmarks;
  }

  Future<NotionSyncResult> _syncBookmark(Topic bookmark) async {
    final detail = await _discourseService.getTopicDetail(bookmark.id);
    if (_isPostBookmark(bookmark)) {
      final post = await _discourseService.getPostByNumber(
        bookmark.id,
        bookmark.bookmarkedPostNumber!,
      );
      return _notionSyncService.syncPost(
        detail: detail,
        post: post,
        onDuplicate: DuplicateAction.skip,
        source: NotionSyncSource.bookmark,
        bookmark: bookmark,
      );
    }

    return _notionSyncService.syncTopic(
      detail: detail,
      scope: config.syncScope,
      onDuplicate: DuplicateAction.skip,
      source: NotionSyncSource.bookmark,
      bookmark: bookmark,
    );
  }

  bool _isPostBookmark(Topic bookmark) {
    return bookmark.bookmarkableType == 'Post' &&
        bookmark.bookmarkedPostNumber != null;
  }
}
