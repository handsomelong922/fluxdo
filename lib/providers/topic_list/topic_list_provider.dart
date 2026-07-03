import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import '../../models/topic.dart';
import '../../services/preloaded_data_service.dart';
import '../../services/discourse/discourse_service.dart';
import '../../services/settings/content_filter_service.dart'; // CUSTOM: Tag Filter // CUSTOM: User Filter
import '../../services/settings/keyword_filter_service.dart'; // CUSTOM: Keyword Filter
import '../../utils/pagination_helper.dart';
import '../core_providers.dart';
import '../category_provider.dart';
import '../message_bus/topic_tracking_providers.dart';
import 'filter_provider.dart';
import 'sort_provider.dart';
import 'tab_state_provider.dart';

final topicListLoadMoreProvider = StateProvider.family<bool, int?>(
  (ref, categoryId) => false,
);
final topicListRefreshingProvider = StateProvider.family<bool, int?>(
  (ref, categoryId) => false,
);
const Duration _topicListProviderRetention = Duration(seconds: 20);

void _retainTopicListProvider(Ref ref, Duration duration) {
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

/// 话题列表 Notifier (支持分页、静默刷新和筛选)
class TopicListNotifier extends AsyncNotifier<List<Topic>> {
  TopicListNotifier(this._categoryId);

  static const int _minInitialVisibleTopics = 20;
  static const int _maxInitialFilterBackfillPages = 2;

  final int? _categoryId;

  int _page = 0;
  bool _hasMore = true;
  bool _isLoadMoreFailed = false;
  int _refreshGeneration = 0;
  bool get hasMore => _hasMore;
  bool get isLoadMoreFailed => _isLoadMoreFailed;

  /// 分页助手
  static final _paginationHelper = PaginationHelpers.forTopics<Topic>(
    keyExtractor: (topic) => topic.id,
  );

  @override
  Future<List<Topic>> build() async {
    _retainTopicListProvider(ref, _topicListProviderRetention);
    ref.onDispose(() => _refreshGeneration++);
    final generation = ++_refreshGeneration;

    // 所有参数使用 ref.read（不建立依赖），
    // 由 UI 层在参数变化时主动 invalidate provider
    final currentFilter = ref.read(topicFilterProvider);
    final tags = ref.read(tabTagsProvider(_categoryId));
    final filter = _buildFilterParams(tags);
    final sortOrder = ref.read(topicSortOrderProvider);
    final sortAscending = ref.read(topicSortAscendingProvider);

    _page = 0;
    _hasMore = true;
    _isLoadMoreFailed = false;
    ref.read(topicListLoadMoreProvider(_categoryId).notifier).state = false;

    // 获取排序 API 参数
    final orderParam = sortOrder.apiValue;
    final ascendingParam = orderParam != null ? sortAscending : null;
    final subset = _subsetForFilter(currentFilter);

    // 优化：如果是 latest 列表且没有筛选条件且没有自定义排序，优先同步使用预加载数据
    // 这样可以避免显示 loading 状态
    if (currentFilter == TopicListFilter.latest &&
        filter.isEmpty &&
        orderParam == null) {
      final preloadedService = PreloadedDataService();
      var preloadedData = preloadedService.getInitialTopicListSync();
      if (preloadedData == null && preloadedService.hasInitialTopicList) {
        preloadedData = await preloadedService.getInitialTopicList().timeout(
          const Duration(seconds: 2),
          onTimeout: () => null,
        );
      }
      if (preloadedData != null) {
        final result = await _processFilteredRefresh(
          service: ref.read(discourseServiceProvider),
          currentFilter: currentFilter,
          filterParams: filter,
          order: orderParam,
          ascending: ascendingParam,
          subset: subset,
          response: preloadedData,
          backfill: false,
        );
        _hasMore = result.state.hasMore;
        _scheduleInitialBackfill(
          generation: generation,
          service: ref.read(discourseServiceProvider),
          currentFilter: currentFilter,
          filterParams: filter,
          order: orderParam,
          ascending: ascendingParam,
          subset: subset,
          initialResult: result,
        );
        return result.state.items;
      }
    }

    // 如果没有预加载数据，走正常的异步流程
    final service = ref.read(discourseServiceProvider);
    final response = await _fetchTopics(
      service,
      currentFilter,
      0,
      filter,
      order: orderParam,
      ascending: ascendingParam,
      subset: subset,
    );

    final result = await _processFilteredRefresh(
      service: service,
      currentFilter: currentFilter,
      filterParams: filter,
      order: orderParam,
      ascending: ascendingParam,
      subset: subset,
      response: response,
      backfill: false,
    );
    _hasMore = result.state.hasMore;
    _scheduleInitialBackfill(
      generation: generation,
      service: service,
      currentFilter: currentFilter,
      filterParams: filter,
      order: orderParam,
      ascending: ascendingParam,
      subset: subset,
      initialResult: result,
    );
    return result.state.items;
  }

  // CUSTOM: Keyword Filter
  // CUSTOM: Tag Filter
  // CUSTOM: User Filter
  List<Topic> _applyTopicFilters(List<Topic> topics) {
    final keywordFilter = ref.read(keywordFilterProvider.notifier);
    final hasKeywordFilters = ref.read(keywordFilterProvider).isNotEmpty;
    final contentFilter = ref.read(contentFilterProvider.notifier);
    final contentState = ref.read(contentFilterProvider);
    final hasContentFilters =
        contentState.hasBlockedTags || contentState.hasBlockedUsers;

    if (!hasKeywordFilters && !hasContentFilters) {
      return topics.where((topic) => !topic.isDeletedPlaceholder).toList();
    }

    return topics.where((topic) {
      if (topic.isDeletedPlaceholder) {
        return false;
      }
      if (hasKeywordFilters && keywordFilter.matches(topic.title)) {
        return false;
      }
      if (hasContentFilters && contentFilter.matchesTopic(topic)) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<_TopicRefreshResult> _processFilteredRefresh({
    required DiscourseService service,
    required TopicListFilter currentFilter,
    required TopicFilterParams filterParams,
    required String? order,
    required bool? ascending,
    required String? subset,
    required TopicListResponse response,
    bool backfill = true,
  }) async {
    var visibleTopics = _dedupeTopics(_applyTopicFilters(response.topics));
    var moreTopicsUrl = response.moreTopicsUrl;
    var lastLoadedPage = 0;

    while (backfill &&
        visibleTopics.length < _minInitialVisibleTopics &&
        moreTopicsUrl != null &&
        lastLoadedPage < _maxInitialFilterBackfillPages) {
      final nextPage = lastLoadedPage + 1;
      final nextResponse = await _fetchTopics(
        service,
        currentFilter,
        nextPage,
        filterParams,
        order: order,
        ascending: ascending,
        subset: subset,
      );
      lastLoadedPage = nextPage;
      moreTopicsUrl = nextResponse.moreTopicsUrl;

      final nextVisible = _applyTopicFilters(nextResponse.topics);
      if (nextVisible.isEmpty) continue;
      visibleTopics = _dedupeTopics([...visibleTopics, ...nextVisible]);
    }

    _page = lastLoadedPage;
    final paginationState = _paginationHelper.processRefresh(
      PaginationResult(items: visibleTopics, moreUrl: moreTopicsUrl),
    );
    return _TopicRefreshResult(
      state: paginationState,
      moreTopicsUrl: moreTopicsUrl,
      lastLoadedPage: lastLoadedPage,
    );
  }

  void _scheduleInitialBackfill({
    required int generation,
    required DiscourseService service,
    required TopicListFilter currentFilter,
    required TopicFilterParams filterParams,
    required String? order,
    required bool? ascending,
    required String? subset,
    required _TopicRefreshResult initialResult,
  }) {
    if (initialResult.state.items.length >= _minInitialVisibleTopics ||
        initialResult.moreTopicsUrl == null ||
        initialResult.lastLoadedPage >= _maxInitialFilterBackfillPages) {
      return;
    }

    unawaited(
      _backfillInitialTopics(
        generation: generation,
        service: service,
        currentFilter: currentFilter,
        filterParams: filterParams,
        order: order,
        ascending: ascending,
        subset: subset,
        initialResult: initialResult,
      ).catchError((Object e) {
        debugPrint('[TopicList] 首屏后台补页失败: $e');
      }),
    );
  }

  Future<void> _backfillInitialTopics({
    required int generation,
    required DiscourseService service,
    required TopicListFilter currentFilter,
    required TopicFilterParams filterParams,
    required String? order,
    required bool? ascending,
    required String? subset,
    required _TopicRefreshResult initialResult,
  }) async {
    var visibleTopics = initialResult.state.items;
    var moreTopicsUrl = initialResult.moreTopicsUrl;
    var lastLoadedPage = initialResult.lastLoadedPage;

    while (generation == _refreshGeneration &&
        visibleTopics.length < _minInitialVisibleTopics &&
        moreTopicsUrl != null &&
        lastLoadedPage < _maxInitialFilterBackfillPages) {
      final nextPage = lastLoadedPage + 1;
      final nextResponse = await _fetchTopics(
        service,
        currentFilter,
        nextPage,
        filterParams,
        order: order,
        ascending: ascending,
        subset: subset,
      );
      if (generation != _refreshGeneration) return;

      lastLoadedPage = nextPage;
      moreTopicsUrl = nextResponse.moreTopicsUrl;

      final nextVisible = _applyTopicFilters(nextResponse.topics);
      if (nextVisible.isEmpty) continue;
      visibleTopics = _dedupeTopics([...visibleTopics, ...nextVisible]);
    }

    if (generation != _refreshGeneration || visibleTopics.isEmpty) return;
    final currentTopics = state.value;
    if (currentTopics == null) return;

    final mergedTopics = _dedupeTopics([...currentTopics, ...visibleTopics]);
    final result = _paginationHelper.processRefresh(
      PaginationResult(items: mergedTopics, moreUrl: moreTopicsUrl),
    );
    if (generation != _refreshGeneration) return;
    if (lastLoadedPage > _page) {
      _page = lastLoadedPage;
    }
    _hasMore = result.hasMore;
    state = AsyncValue.data(result.items);
  }

  List<Topic> _dedupeTopics(List<Topic> topics) {
    final seen = <int>{};
    final result = <Topic>[];
    for (final topic in topics) {
      if (seen.add(topic.id)) {
        result.add(topic);
      }
    }
    return result;
  }

  Future<TopicListResponse> _fetchTopics(
    DiscourseService service,
    TopicListFilter filter,
    int page,
    TopicFilterParams filterParams, {
    String? order,
    bool? ascending,
    String? subset,
  }) {
    // 如果有筛选条件，使用 getFilteredTopics
    if (filterParams.isNotEmpty) {
      final filterName = _getFilterName(filter);
      return service.getFilteredTopics(
        filter: filterName,
        categoryId: filterParams.categoryId,
        categorySlug: filterParams.categorySlug,
        parentCategorySlug: filterParams.parentCategorySlug,
        tags: filterParams.tags.isNotEmpty ? filterParams.tags : null,
        period: filter.period,
        page: page,
        order: order,
        ascending: ascending,
        subset: subset,
      );
    }

    // 无筛选条件，使用原有方法
    switch (filter) {
      case TopicListFilter.latest:
        return service.getLatestTopics(
          page: page,
          order: order,
          ascending: ascending,
        );
      case TopicListFilter.newTopics:
        return service.getNewTopics(
          page: page,
          order: order,
          ascending: ascending,
          subset: subset,
        );
      case TopicListFilter.unread:
        return service.getUnreadTopics(
          page: page,
          order: order,
          ascending: ascending,
        );
      case TopicListFilter.unseen:
        return service.getUnseenTopics(
          page: page,
          order: order,
          ascending: ascending,
        );
      case TopicListFilter.top:
        return service.getTopTopics();
      case TopicListFilter.hot:
        return service.getHotTopics(
          page: page,
          order: order,
          ascending: ascending,
        );
    }
  }

  String _getFilterName(TopicListFilter filter) => filter.filterName;

  /// 根据分类 ID 和标签构建筛选参数
  TopicFilterParams _buildFilterParams(List<String> tags) {
    if (_categoryId == null && tags.isEmpty) {
      return const TopicFilterParams();
    }
    if (_categoryId != null) {
      final categoryMap = ref.read(categoryMapProvider).value ?? {};
      final category = categoryMap[_categoryId];
      String? parentSlug;
      if (category?.parentCategoryId != null) {
        parentSlug = categoryMap[category!.parentCategoryId]?.slug;
      }
      return TopicFilterParams(
        categoryId: _categoryId,
        categorySlug: category?.slug,
        categoryName: category?.name,
        parentCategorySlug: parentSlug,
        tags: tags,
      );
    }
    return TopicFilterParams(tags: tags);
  }

  /// 获取当前筛选参数（供非 build 方法使用）
  TopicFilterParams _currentFilterParams() {
    return _buildFilterParams(ref.read(tabTagsProvider(_categoryId)));
  }

  /// 获取当前筛选模式
  TopicListFilter get _currentFilter => ref.read(topicFilterProvider);

  String? _subsetForFilter(TopicListFilter filter) {
    return filter == TopicListFilter.newTopics
        ? ref.read(topicNewSubsetProvider).apiValue
        : null;
  }

  /// 获取当前排序参数
  (String?, bool?) _currentSortParams() {
    final sortOrder = ref.read(topicSortOrderProvider);
    final orderParam = sortOrder.apiValue;
    final ascendingParam = orderParam != null
        ? ref.read(topicSortAscendingProvider)
        : null;
    return (orderParam, ascendingParam);
  }

  /// 刷新列表
  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    final refreshingState = topicListRefreshingProvider(_categoryId);
    final currentTopics = state.value;
    if (currentTopics == null) {
      state = const AsyncValue.loading();
    } else {
      ref.read(refreshingState.notifier).state = true;
    }

    final result = await AsyncValue.guard(() async {
      _page = 0;
      _hasMore = true;
      _isLoadMoreFailed = false;
      final service = ref.read(discourseServiceProvider);
      final filterParams = _currentFilterParams();
      final (order, ascending) = _currentSortParams();
      final currentFilter = _currentFilter;
      final response = await _fetchTopics(
        service,
        currentFilter,
        0,
        filterParams,
        order: order,
        ascending: ascending,
        subset: _subsetForFilter(currentFilter),
      );

      final result = await _processFilteredRefresh(
        service: service,
        currentFilter: currentFilter,
        filterParams: filterParams,
        order: order,
        ascending: ascending,
        subset: _subsetForFilter(currentFilter),
        response: response,
        backfill: false,
      );
      _hasMore = result.state.hasMore;
      _scheduleInitialBackfill(
        generation: generation,
        service: service,
        currentFilter: currentFilter,
        filterParams: filterParams,
        order: order,
        ascending: ascending,
        subset: _subsetForFilter(currentFilter),
        initialResult: result,
      );
      return result.state.items;
    });

    if (currentTopics != null) {
      ref.read(refreshingState.notifier).state = false;
      if (result.hasError) {
        state = AsyncValue.data(currentTopics);
      } else {
        state = result;
      }
      return;
    }

    state = result;
  }

  /// 静默刷新
  Future<void> silentRefresh() async {
    final generation = ++_refreshGeneration;
    final service = ref.read(discourseServiceProvider);
    final filterParams = _currentFilterParams();
    final (order, ascending) = _currentSortParams();
    final currentFilter = _currentFilter;
    try {
      final response = await _fetchTopics(
        service,
        currentFilter,
        0,
        filterParams,
        order: order,
        ascending: ascending,
        subset: _subsetForFilter(currentFilter),
      );
      _page = 0;
      _isLoadMoreFailed = false;

      final result = await _processFilteredRefresh(
        service: service,
        currentFilter: currentFilter,
        filterParams: filterParams,
        order: order,
        ascending: ascending,
        subset: _subsetForFilter(currentFilter),
        response: response,
        backfill: false,
      );
      _hasMore = result.state.hasMore;
      state = AsyncValue.data(result.state.items);
      _scheduleInitialBackfill(
        generation: generation,
        service: service,
        currentFilter: currentFilter,
        filterParams: filterParams,
        order: order,
        ascending: ascending,
        subset: _subsetForFilter(currentFilter),
        initialResult: result,
      );
    } catch (e) {
      debugPrint('Silent refresh failed: $e');
    }
  }

  /// 按 topic_ids 加载并插入到列表顶部（对齐网页版 loadBefore）
  ///
  /// 1. 请求 /latest.json?topic_ids=xxx 获取这些话题的最新数据
  /// 2. 从当前列表中移除同 ID 旧数据（处理"更新的话题"）
  /// 3. 将 API 返回的话题全部插入列表顶部
  ///
  /// 返回实际被插入到顶部的 topic IDs（用于 UI 高亮）
  Future<List<int>> loadBefore(List<int> topicIds) async {
    if (topicIds.isEmpty) return [];
    final currentTopics = state.value;
    if (currentTopics == null) return [];

    try {
      final service = ref.read(discourseServiceProvider);
      final response = await service.getTopicsByIds(topicIds);
      final newTopics = response.topics;
      if (newTopics.isEmpty) return [];

      // CUSTOM: Keyword Filter
      // CUSTOM: Tag Filter
      // CUSTOM: User Filter
      final filteredNewTopics = _applyTopicFilters(newTopics);
      if (filteredNewTopics.isEmpty) return [];

      // 移除列表中已存在的同 ID 话题（刷新重复项，与网页版 removeValuesFromArray 一致）
      final newTopicIds = filteredNewTopics.map((t) => t.id).toSet();
      final remaining = currentTopics
          .where((t) => !newTopicIds.contains(t.id))
          .toList();
      // 将新话题全部插入列表顶部
      state = AsyncValue.data([...filteredNewTopics, ...remaining]);
      return filteredNewTopics.map((t) => t.id).toList();
    } catch (e) {
      debugPrint('[TopicList] loadBefore 失败: $e');
      return [];
    }
  }

  /// 加载更多
  Future<void> loadMore() async {
    if (_isLoadMoreFailed) return; // 失败后需手动重试
    if (!_hasMore || state.isLoading) return;
    final loadMoreState = topicListLoadMoreProvider(_categoryId);
    if (ref.read(topicListRefreshingProvider(_categoryId))) return;
    if (ref.read(loadMoreState)) return;
    final currentTopics = state.value;
    if (currentTopics == null) return;

    ref.read(loadMoreState.notifier).state = true;

    try {
      final nextPage = _page + 1;

      final service = ref.read(discourseServiceProvider);
      final filterParams = _currentFilterParams();
      final (order, ascending) = _currentSortParams();
      final currentFilter = _currentFilter;
      final response = await _fetchTopics(
        service,
        currentFilter,
        nextPage,
        filterParams,
        order: order,
        ascending: ascending,
        subset: _subsetForFilter(currentFilter),
      );

      final currentState = PaginationState<Topic>(items: currentTopics);
      final paginationResult = _paginationHelper.processLoadMore(
        currentState,
        // CUSTOM: Keyword Filter 先过滤掉命中关键词的新帖，再合并
        PaginationResult(
          items: _applyTopicFilters(response.topics),
          moreUrl: response.moreTopicsUrl,
        ),
      );

      _hasMore = paginationResult.hasMore;
      if (paginationResult.items.length > currentTopics.length) {
        _page = nextPage;
      }
      state = AsyncValue.data(paginationResult.items);
    } catch (_) {
      _isLoadMoreFailed = true;
      state = AsyncValue.data(currentTopics);
    } finally {
      ref.read(loadMoreState.notifier).state = false;
    }
  }

  /// 手动重试加载更多
  void retryLoadMore() {
    _isLoadMoreFailed = false;
    loadMore();
  }

  /// 刷新单条话题状态（用于 MessageBus 更新）
  Future<void> refreshTopic(int topicId) async {
    final currentTopics = state.value;
    if (currentTopics == null) return;

    final existingIndex = currentTopics.indexWhere((t) => t.id == topicId);
    if (existingIndex == -1) {
      return;
    }
    final existingTopic = currentTopics[existingIndex];

    try {
      final service = ref.read(discourseServiceProvider);
      final detail = await service.getTopicDetail(topicId);
      final firstPostCooked = detail.postStream.posts.isNotEmpty
          ? detail.postStream.posts.first.cooked
          : null;

      final updatedTopic = Topic(
        id: detail.id,
        title: detail.title,
        fancyTitle: existingTopic.fancyTitle,
        slug: detail.slug,
        categoryId: detail.categoryId.toString(),
        postsCount: detail.postsCount,
        replyCount: detail.postsCount > 0 ? detail.postsCount - 1 : 0,
        views: existingTopic.views,
        likeCount: existingTopic.likeCount,
        excerpt: firstPostCooked,
        lastPostedAt: existingTopic.lastPostedAt,
        pinned: existingTopic.pinned,
        visible: detail.visible,
        closed: detail.closed,
        archived: detail.archived,
        tags: detail.tags ?? existingTopic.tags,
        posters: existingTopic.posters,
        unseen: false,
        unread: 0,
        lastReadPostNumber: detail.postsCount,
        highestPostNumber: detail.postsCount,
        lastPosterUsername: detail.postStream.posts.isNotEmpty
            ? detail.postStream.posts.last.username
            : existingTopic.lastPosterUsername,
      );

      if (updatedTopic.isDeletedPlaceholder) {
        state = AsyncValue.data(
          currentTopics.where((t) => t.id != topicId).toList(),
        );
        return;
      }

      final newList = currentTopics.map((t) {
        return t.id == topicId ? updatedTopic : t;
      }).toList();

      state = AsyncValue.data(newList);
    } catch (e) {
      debugPrint('[TopicList] 刷新话题 $topicId 失败: $e');
    }
  }

  /// 忽略全部（新话题或未读话题）
  Future<void> dismissAll() async {
    final service = ref.read(discourseServiceProvider);
    final filter = _currentFilter;
    if (filter == TopicListFilter.newTopics) {
      final subset = ref.read(topicNewSubsetProvider);
      await service.dismissNewTopics(
        categoryId: _categoryId,
        dismissTopics: subset != NewSubset.replies,
        dismissPosts: subset != NewSubset.topics,
      );
      final trackingNotifier = ref.read(topicTrackingStateProvider.notifier);
      if (subset != NewSubset.replies) {
        trackingNotifier.dismissNewTopics(categoryId: _categoryId);
      }
      if (subset != NewSubset.topics) {
        trackingNotifier.dismissUnreadTopics(categoryId: _categoryId);
      }
    } else if (filter == TopicListFilter.unread) {
      await service.dismissUnreadTopics(categoryId: _categoryId);
      // 同步更新追踪状态计数
      ref
          .read(topicTrackingStateProvider.notifier)
          .dismissUnreadTopics(categoryId: _categoryId);
    }
    state = const AsyncValue.data([]);
    _hasMore = false;
  }

  void updateSeen(int topicId, int highestSeen) {
    final topics = state.value;
    if (topics == null) return;

    final index = topics.indexWhere((t) => t.id == topicId);
    if (index == -1) return;

    final topic = topics[index];
    final currentRead = topic.lastReadPostNumber ?? 0;

    if (highestSeen <= currentRead) return;

    final newUnread = (topic.highestPostNumber - highestSeen).clamp(
      0,
      topic.highestPostNumber,
    );

    final updated = Topic(
      id: topic.id,
      title: topic.title,
      fancyTitle: topic.fancyTitle,
      slug: topic.slug,
      postsCount: topic.postsCount,
      replyCount: topic.replyCount,
      views: topic.views,
      likeCount: topic.likeCount,
      excerpt: topic.excerpt,
      createdAt: topic.createdAt,
      lastPostedAt: topic.lastPostedAt,
      lastPosterUsername: topic.lastPosterUsername,
      categoryId: topic.categoryId,
      pinned: topic.pinned,
      visible: topic.visible,
      closed: topic.closed,
      archived: topic.archived,
      deletedAt: topic.deletedAt,
      userDeleted: topic.userDeleted,
      tags: topic.tags,
      posters: topic.posters,
      unseen: false,
      unread: newUnread,
      newPosts: 0,
      lastReadPostNumber: highestSeen,
      highestPostNumber: topic.highestPostNumber,
    );

    final newList = [...topics];
    newList[index] = updated;
    state = AsyncValue.data(newList);

    // 同步更新追踪状态计数（阅读后减少 new/unread 计数）
    ref
        .read(topicTrackingStateProvider.notifier)
        .updateTopicRead(topicId, highestSeen, topic.highestPostNumber);
  }
}

class _TopicRefreshResult {
  const _TopicRefreshResult({
    required this.state,
    required this.moreTopicsUrl,
    required this.lastLoadedPage,
  });

  final PaginationState<Topic> state;
  final String? moreTopicsUrl;
  final int lastLoadedPage;
}

final topicListProvider =
    AsyncNotifierProvider.family.autoDispose<TopicListNotifier, List<Topic>, int?>(
      TopicListNotifier.new,
    );

/// 热门话题 Provider
final topTopicsProvider = FutureProvider<TopicListResponse>((ref) async {
  final service = ref.watch(discourseServiceProvider);
  return service.getTopTopics();
});
