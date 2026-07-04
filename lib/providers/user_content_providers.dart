import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import '../models/topic.dart';
import '../utils/pagination_helper.dart';
import 'core_providers.dart';

final browsingHistoryLoadMoreProvider = StateProvider<bool>((ref) => false);
final bookmarksLoadMoreProvider = StateProvider<bool>((ref) => false);
final browsingHistoryRefreshingProvider = StateProvider<bool>((ref) => false);
final bookmarksRefreshingProvider = StateProvider<bool>((ref) => false);
const Duration _userContentProviderRetention = Duration(seconds: 20);
const Duration _userContentProviderRetentionMobile = Duration(seconds: 5);

Duration _resolvedUserContentProviderRetention() {
  return (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)
      ? _userContentProviderRetentionMobile
      : _userContentProviderRetention;
}

void _retainAutoDisposeState(Ref ref, Duration duration) {
  final link = ref.keepAlive();
  Timer? disposeTimer;
  ref.onCancel(() {
    disposeTimer = Timer(duration, link.close);
  });
  ref.onResume(() {
    disposeTimer?.cancel();
    disposeTimer = null;
  });
  ref.onDispose(() {
    disposeTimer?.cancel();
  });
}

/// 分页助手（所有用户内容列表共用）
final _topicPaginationHelper = PaginationHelpers.forTopics<Topic>(
  keyExtractor: (topic) => topic.id,
);

/// 浏览历史 Notifier (支持分页)
class BrowsingHistoryNotifier extends AsyncNotifier<List<Topic>> {
  int _page = 0;
  bool _hasMore = true;
  bool _isLoadMoreFailed = false;
  bool get hasMore => _hasMore;
  bool get isLoadMoreFailed => _isLoadMoreFailed;

  @override
  Future<List<Topic>> build() async {
    _retainAutoDisposeState(ref, _resolvedUserContentProviderRetention());
    _page = 0;
    _hasMore = true;
    _isLoadMoreFailed = false;
    ref.read(browsingHistoryLoadMoreProvider.notifier).state = false;
    final service = ref.read(discourseServiceProvider);
    final response = await service.getBrowsingHistory(page: 0);

    final result = _topicPaginationHelper.processRefresh(
      PaginationResult(items: response.topics, moreUrl: response.moreTopicsUrl),
    );
    _hasMore = result.hasMore;
    return result.items;
  }

  Future<void> refresh() async {
    _isLoadMoreFailed = false;
    final currentList = state.value;
    if (currentList == null) {
      state = const AsyncValue.loading();
    } else {
      ref.read(browsingHistoryRefreshingProvider.notifier).state = true;
    }

    final result = await AsyncValue.guard(() async {
      _page = 0;
      _hasMore = true;
      final service = ref.read(discourseServiceProvider);
      final response = await service.getBrowsingHistory(page: 0);

      final result = _topicPaginationHelper.processRefresh(
        PaginationResult(
          items: response.topics,
          moreUrl: response.moreTopicsUrl,
        ),
      );
      _hasMore = result.hasMore;
      return result.items;
    });

    if (currentList != null) {
      ref.read(browsingHistoryRefreshingProvider.notifier).state = false;
      if (result.hasError) {
        state = AsyncValue.data(currentList);
      } else {
        state = result;
      }
      return;
    }

    state = result;
  }

  Future<void> loadMore() async {
    if (_isLoadMoreFailed) return;
    if (!_hasMore || state.isLoading) return;
    if (ref.read(browsingHistoryRefreshingProvider)) return;
    if (ref.read(browsingHistoryLoadMoreProvider)) return;
    final currentList = state.value;
    if (currentList == null) return;

    ref.read(browsingHistoryLoadMoreProvider.notifier).state = true;

    try {
      final nextPage = _page + 1;

      final service = ref.read(discourseServiceProvider);
      final response = await service.getBrowsingHistory(page: nextPage);

      final currentState = PaginationState<Topic>(items: currentList);
      final paginationResult = _topicPaginationHelper.processLoadMore(
        currentState,
        PaginationResult(
          items: response.topics,
          moreUrl: response.moreTopicsUrl,
        ),
      );

      _hasMore = paginationResult.hasMore;
      if (paginationResult.items.length > currentList.length) {
        _page = nextPage;
      }
      state = AsyncValue.data(paginationResult.items);
    } catch (_) {
      _isLoadMoreFailed = true;
      state = AsyncValue.data(currentList);
    } finally {
      ref.read(browsingHistoryLoadMoreProvider.notifier).state = false;
    }
  }

  void retryLoadMore() {
    _isLoadMoreFailed = false;
    loadMore();
  }
}

final browsingHistoryProvider =
    AsyncNotifierProvider.autoDispose<BrowsingHistoryNotifier, List<Topic>>(() {
      return BrowsingHistoryNotifier();
    });

/// 书签 Notifier (支持分页)
class BookmarksNotifier extends AsyncNotifier<List<Topic>> {
  int _page = 0;
  bool _hasMore = true;
  bool _isLoadMoreFailed = false;
  bool get hasMore => _hasMore;
  bool get isLoadMoreFailed => _isLoadMoreFailed;

  @override
  Future<List<Topic>> build() async {
    _retainAutoDisposeState(ref, _resolvedUserContentProviderRetention());
    _page = 0;
    _hasMore = true;
    _isLoadMoreFailed = false;
    ref.read(bookmarksLoadMoreProvider.notifier).state = false;
    final service = ref.read(discourseServiceProvider);
    final response = await service.getUserBookmarks(page: 0);

    final result = _topicPaginationHelper.processRefresh(
      PaginationResult(items: response.topics, moreUrl: response.moreTopicsUrl),
    );
    _hasMore = result.hasMore;
    return result.items;
  }

  Future<void> refresh() async {
    _isLoadMoreFailed = false;
    final currentList = state.value;
    if (currentList == null) {
      state = const AsyncValue.loading();
    } else {
      ref.read(bookmarksRefreshingProvider.notifier).state = true;
    }

    final result = await AsyncValue.guard(() async {
      _page = 0;
      _hasMore = true;
      final service = ref.read(discourseServiceProvider);
      final response = await service.getUserBookmarks(page: 0);

      final result = _topicPaginationHelper.processRefresh(
        PaginationResult(
          items: response.topics,
          moreUrl: response.moreTopicsUrl,
        ),
      );
      _hasMore = result.hasMore;
      return result.items;
    });

    if (currentList != null) {
      ref.read(bookmarksRefreshingProvider.notifier).state = false;
      if (result.hasError) {
        state = AsyncValue.data(currentList);
      } else {
        state = result;
      }
      return;
    }

    state = result;
  }

  Future<void> loadMore() async {
    if (_isLoadMoreFailed) return;
    if (!_hasMore || state.isLoading) return;
    if (ref.read(bookmarksRefreshingProvider)) return;
    if (ref.read(bookmarksLoadMoreProvider)) return;
    final currentList = state.value;
    if (currentList == null) return;

    ref.read(bookmarksLoadMoreProvider.notifier).state = true;

    try {
      final nextPage = _page + 1;

      final service = ref.read(discourseServiceProvider);
      final response = await service.getUserBookmarks(page: nextPage);

      final currentState = PaginationState<Topic>(items: currentList);
      final paginationResult = _topicPaginationHelper.processLoadMore(
        currentState,
        PaginationResult(
          items: response.topics,
          moreUrl: response.moreTopicsUrl,
        ),
      );

      _hasMore = paginationResult.hasMore;
      if (paginationResult.items.length > currentList.length) {
        _page = nextPage;
      }
      state = AsyncValue.data(paginationResult.items);
    } catch (_) {
      _isLoadMoreFailed = true;
      state = AsyncValue.data(currentList);
    } finally {
      ref.read(bookmarksLoadMoreProvider.notifier).state = false;
    }
  }

  void retryLoadMore() {
    _isLoadMoreFailed = false;
    loadMore();
  }

  /// 从本地列表中移除指定书签（删除后调用）
  void removeBookmarkById(int bookmarkId) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(
      current.where((t) => t.bookmarkId != bookmarkId).toList(),
    );
  }

  /// 更新本地列表中指定书签的元数据
  void updateBookmarkMeta(
    int bookmarkId, {
    String? name,
    DateTime? reminderAt,
    bool clearReminderAt = false,
  }) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(
      current.map((t) {
        if (t.bookmarkId != bookmarkId) return t;
        return Topic(
          id: t.id,
          title: t.title,
          fancyTitle: t.fancyTitle,
          slug: t.slug,
          postsCount: t.postsCount,
          replyCount: t.replyCount,
          views: t.views,
          likeCount: t.likeCount,
          excerpt: t.excerpt,
          createdAt: t.createdAt,
          lastPostedAt: t.lastPostedAt,
          lastPosterUsername: t.lastPosterUsername,
          categoryId: t.categoryId,
          pinned: t.pinned,
          visible: t.visible,
          closed: t.closed,
          archived: t.archived,
          deletedAt: t.deletedAt,
          userDeleted: t.userDeleted,
          tags: t.tags,
          posters: t.posters,
          unseen: t.unseen,
          unread: t.unread,
          newPosts: t.newPosts,
          lastReadPostNumber: t.lastReadPostNumber,
          highestPostNumber: t.highestPostNumber,
          bookmarkedPostNumber: t.bookmarkedPostNumber,
          bookmarkId: t.bookmarkId,
          bookmarkName: name ?? t.bookmarkName,
          bookmarkReminderAt: clearReminderAt
              ? null
              : (reminderAt ?? t.bookmarkReminderAt),
          bookmarkableType: t.bookmarkableType,
          bookmarkCreatedAt: t.bookmarkCreatedAt,
          hasAcceptedAnswer: t.hasAcceptedAnswer,
          canHaveAnswer: t.canHaveAnswer,
        );
      }).toList(),
    );
  }
}

final bookmarksProvider =
    AsyncNotifierProvider.autoDispose<BookmarksNotifier, List<Topic>>(() {
      return BookmarksNotifier();
    });

/// 我的话题 Notifier (支持分页)
class MyTopicsNotifier extends AsyncNotifier<List<Topic>> {
  int _page = 0;
  bool _hasMore = true;
  bool _isLoadMoreFailed = false;
  bool get hasMore => _hasMore;
  bool get isLoadMoreFailed => _isLoadMoreFailed;

  @override
  Future<List<Topic>> build() async {
    _retainAutoDisposeState(ref, _resolvedUserContentProviderRetention());
    _page = 0;
    _hasMore = true;
    _isLoadMoreFailed = false;
    final service = ref.read(discourseServiceProvider);
    final response = await service.getUserCreatedTopics(page: 0);

    final result = _topicPaginationHelper.processRefresh(
      PaginationResult(items: response.topics, moreUrl: response.moreTopicsUrl),
    );
    _hasMore = result.hasMore;
    return result.items;
  }

  Future<void> refresh() async {
    _isLoadMoreFailed = false;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      _page = 0;
      _hasMore = true;
      final service = ref.read(discourseServiceProvider);
      final response = await service.getUserCreatedTopics(page: 0);

      final result = _topicPaginationHelper.processRefresh(
        PaginationResult(
          items: response.topics,
          moreUrl: response.moreTopicsUrl,
        ),
      );
      _hasMore = result.hasMore;
      return result.items;
    });
  }

  Future<void> loadMore() async {
    if (_isLoadMoreFailed) return;
    if (!_hasMore || state.isLoading) return;

    // ignore: invalid_use_of_internal_member
    state = const AsyncLoading<List<Topic>>().copyWithPrevious(state);

    final result = await AsyncValue.guard(() async {
      final currentList = state.requireValue;
      final nextPage = _page + 1;

      final service = ref.read(discourseServiceProvider);
      final response = await service.getUserCreatedTopics(page: nextPage);

      final currentState = PaginationState(items: currentList);
      final paginationResult = _topicPaginationHelper.processLoadMore(
        currentState,
        PaginationResult(
          items: response.topics,
          moreUrl: response.moreTopicsUrl,
        ),
      );

      _hasMore = paginationResult.hasMore;
      if (paginationResult.items.length > currentList.length) {
        _page = nextPage;
      }
      return paginationResult.items;
    });
    if (result.hasError) {
      _isLoadMoreFailed = true;
      state = AsyncValue.data(state.requireValue);
    } else {
      state = result;
    }
  }

  void retryLoadMore() {
    _isLoadMoreFailed = false;
    loadMore();
  }
}

final myTopicsProvider =
    AsyncNotifierProvider.autoDispose<MyTopicsNotifier, List<Topic>>(() {
      return MyTopicsNotifier();
    });

/// 私信筛选类型
enum PrivateMessageFilter { inbox, sent, archive }

/// 私信列表 Notifier 基类 (支持分页)
abstract class PrivateMessagesNotifier extends AsyncNotifier<List<Topic>> {
  int _page = 0;
  bool _hasMore = true;
  bool _isLoadMoreFailed = false;
  bool get hasMore => _hasMore;
  bool get isLoadMoreFailed => _isLoadMoreFailed;

  Future<TopicListResponse> fetch(int page);

  @override
  Future<List<Topic>> build() async {
    _retainAutoDisposeState(ref, _resolvedUserContentProviderRetention());
    _page = 0;
    _hasMore = true;
    _isLoadMoreFailed = false;
    final response = await fetch(0);

    final result = _topicPaginationHelper.processRefresh(
      PaginationResult(items: response.topics, moreUrl: response.moreTopicsUrl),
    );
    _hasMore = result.hasMore;
    return result.items;
  }

  Future<void> refresh() async {
    _isLoadMoreFailed = false;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      _page = 0;
      _hasMore = true;
      final response = await fetch(0);

      final result = _topicPaginationHelper.processRefresh(
        PaginationResult(
          items: response.topics,
          moreUrl: response.moreTopicsUrl,
        ),
      );
      _hasMore = result.hasMore;
      return result.items;
    });
  }

  Future<void> loadMore() async {
    if (_isLoadMoreFailed) return;
    if (!_hasMore || state.isLoading) return;

    // ignore: invalid_use_of_internal_member
    state = const AsyncLoading<List<Topic>>().copyWithPrevious(state);

    final result = await AsyncValue.guard(() async {
      final currentList = state.requireValue;
      final nextPage = _page + 1;

      final response = await fetch(nextPage);

      final currentState = PaginationState<Topic>(items: currentList);
      final paginationResult = _topicPaginationHelper.processLoadMore(
        currentState,
        PaginationResult(
          items: response.topics,
          moreUrl: response.moreTopicsUrl,
        ),
      );

      _hasMore = paginationResult.hasMore;
      if (paginationResult.items.length > currentList.length) {
        _page = nextPage;
      }
      return paginationResult.items;
    });
    if (result.hasError) {
      _isLoadMoreFailed = true;
      state = AsyncValue.data(state.requireValue);
    } else {
      state = result;
    }
  }

  void retryLoadMore() {
    _isLoadMoreFailed = false;
    loadMore();
  }
}

class _PmInboxNotifier extends PrivateMessagesNotifier {
  @override
  Future<TopicListResponse> fetch(int page) =>
      ref.read(discourseServiceProvider).getPrivateMessages(page: page);
}

class _PmSentNotifier extends PrivateMessagesNotifier {
  @override
  Future<TopicListResponse> fetch(int page) =>
      ref.read(discourseServiceProvider).getPrivateMessagesSent(page: page);
}

class _PmArchiveNotifier extends PrivateMessagesNotifier {
  @override
  Future<TopicListResponse> fetch(int page) =>
      ref.read(discourseServiceProvider).getPrivateMessagesArchive(page: page);
}

final pmInboxProvider =
    AsyncNotifierProvider.autoDispose<_PmInboxNotifier, List<Topic>>(
      () => _PmInboxNotifier(),
    );
final pmSentProvider =
    AsyncNotifierProvider.autoDispose<_PmSentNotifier, List<Topic>>(
      () => _PmSentNotifier(),
    );
final pmArchiveProvider =
    AsyncNotifierProvider.autoDispose<_PmArchiveNotifier, List<Topic>>(
      () => _PmArchiveNotifier(),
    );
