import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/nested_topic.dart';
import '../models/topic.dart';
import 'core_providers.dart';

/// 嵌套视图参数
class NestedTopicParams {
  final int topicId;

  const NestedTopicParams({required this.topicId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NestedTopicParams && topicId == other.topicId;

  @override
  int get hashCode => topicId.hashCode;
}

/// 嵌套视图状态
class NestedTopicState {
  final Map<String, dynamic>? topicJson;
  final Post? opPost;
  final List<NestedNode> roots;
  final bool hasMoreRoots;
  final int currentPage;
  final String sort;
  final int? pinnedPostNumber;
  final bool isLoadingMore;
  final bool isRefreshingSort;
  final List<int> newRootPostIds;
  final NestedChildCreatedEvent? lastChildCreated;

  const NestedTopicState({
    this.topicJson,
    this.opPost,
    this.roots = const [],
    this.hasMoreRoots = false,
    this.currentPage = 0,
    this.sort = 'top',
    this.pinnedPostNumber,
    this.isLoadingMore = false,
    this.isRefreshingSort = false,
    this.newRootPostIds = const [],
    this.lastChildCreated,
  });

  String get title => topicJson?['title'] as String? ?? '';

  NestedTopicState copyWith({
    Map<String, dynamic>? topicJson,
    Post? opPost,
    List<NestedNode>? roots,
    bool? hasMoreRoots,
    int? currentPage,
    String? sort,
    int? pinnedPostNumber,
    bool? isLoadingMore,
    bool? isRefreshingSort,
    List<int>? newRootPostIds,
    NestedChildCreatedEvent? lastChildCreated,
    bool clearLastChildCreated = false,
  }) {
    return NestedTopicState(
      topicJson: topicJson ?? this.topicJson,
      opPost: opPost ?? this.opPost,
      roots: roots ?? this.roots,
      hasMoreRoots: hasMoreRoots ?? this.hasMoreRoots,
      currentPage: currentPage ?? this.currentPage,
      sort: sort ?? this.sort,
      pinnedPostNumber: pinnedPostNumber ?? this.pinnedPostNumber,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isRefreshingSort: isRefreshingSort ?? this.isRefreshingSort,
      newRootPostIds: newRootPostIds ?? this.newRootPostIds,
      lastChildCreated: clearLastChildCreated
          ? null
          : (lastChildCreated ?? this.lastChildCreated),
    );
  }
}

/// 嵌套视图 Notifier
class NestedTopicNotifier extends AsyncNotifier<NestedTopicState> {
  NestedTopicNotifier(this.arg);
  final NestedTopicParams arg;

  @override
  Future<NestedTopicState> build() async {
    final service = ref.read(discourseServiceProvider);
    final response = await service.getNestedRoots(
      arg.topicId,
      sort: 'top',
      page: 0,
      trackVisit: true,
    );

    return NestedTopicState(
      topicJson: response.topicJson,
      opPost: response.opPost,
      roots: response.roots,
      hasMoreRoots: response.hasMoreRoots,
      currentPage: 0,
      sort: response.sort ?? 'top',
      pinnedPostNumber: response.pinnedPostNumber,
    );
  }

  /// 加载更多根帖子
  Future<void> loadMoreRoots() async {
    final current = state.value;
    if (current == null || !current.hasMoreRoots || current.isLoadingMore) {
      return;
    }

    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    state = AsyncValue.data(current.copyWith(isLoadingMore: true));

    try {
      final service = ref.read(discourseServiceProvider);
      final nextPage = current.currentPage + 1;
      final response = await service.getNestedRoots(
        arg.topicId,
        sort: current.sort,
        page: nextPage,
      );

      if (!ref.mounted) return;
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      state = AsyncValue.data(
        current.copyWith(
          roots: [...current.roots, ...response.roots],
          hasMoreRoots: response.hasMoreRoots,
          currentPage: nextPage,
          isLoadingMore: false,
        ),
      );
    } catch (e) {
      debugPrint('[NestedTopic] loadMoreRoots failed: $e');
      if (!ref.mounted) return;
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      state = AsyncValue.data(current.copyWith(isLoadingMore: false));
    }
  }

  /// 切换排序
  Future<void> changeSort(String newSort) async {
    final current = state.value;
    if (current == null || current.sort == newSort) return;

    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    state = AsyncValue.data(
      current.copyWith(sort: newSort, isRefreshingSort: true),
    );

    try {
      final service = ref.read(discourseServiceProvider);
      final response = await service.getNestedRoots(
        arg.topicId,
        sort: newSort,
        page: 0,
      );

      if (!ref.mounted) return;
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      state = AsyncValue.data(
        current.copyWith(
          roots: response.roots,
          hasMoreRoots: response.hasMoreRoots,
          currentPage: 0,
          sort: newSort,
          pinnedPostNumber: response.pinnedPostNumber,
          isRefreshingSort: false,
          isLoadingMore: false,
          newRootPostIds: const [],
        ),
      );
    } catch (e, s) {
      if (!ref.mounted) return;
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      state = AsyncValue.data(current.copyWith(isRefreshingSort: false));
      debugPrint('[NestedTopic] changeSort failed: $e\n$s');
    }
  }

  /// 懒加载子回复
  Future<NestedChildrenResponse> loadChildren(
    int postNumber, {
    int page = 0,
    int depth = 1,
  }) async {
    final current = state.value;
    final service = ref.read(discourseServiceProvider);
    return service.getNestedChildren(
      arg.topicId,
      postNumber,
      sort: current?.sort ?? 'top',
      page: page,
      depth: depth,
    );
  }

  /// 添加新帖子（自己回复或 MessageBus created 事件）。
  void addNewPost(Post post, {required bool isOwnPost}) {
    final current = state.value;
    if (current == null) return;
    if (_containsPostId(current.roots, post.id) ||
        current.opPost?.id == post.id) {
      return;
    }

    final replyTo = post.replyToPostNumber;
    final isRootReply = replyTo <= 0 || replyTo == 1;

    if (isRootReply) {
      if (isOwnPost) {
        state = AsyncValue.data(
          current.copyWith(
            roots: [
              NestedNode(post: post),
              ...current.roots,
            ],
          ),
        );
      } else if (!current.newRootPostIds.contains(post.id)) {
        state = AsyncValue.data(
          current.copyWith(
            newRootPostIds: [...current.newRootPostIds, post.id],
          ),
        );
      }
      return;
    }

    state = AsyncValue.data(
      current.copyWith(
        lastChildCreated: NestedChildCreatedEvent(
          post: post,
          parentPostNumber: replyTo,
        ),
      ),
    );
  }

  /// 加载 MessageBus 发现但尚未插入的根回复。
  Future<void> loadNewRoots() async {
    final current = state.value;
    if (current == null || current.newRootPostIds.isEmpty) return;

    final ids = List<int>.from(current.newRootPostIds);
    state = AsyncValue.data(current.copyWith(newRootPostIds: []));

    try {
      final service = ref.read(discourseServiceProvider);
      final newNodes = <NestedNode>[];
      for (final id in ids) {
        try {
          final post = await service.getPost(id);
          newNodes.add(NestedNode(post: post));
        } catch (e) {
          debugPrint('[NestedTopic] loadNewRoots: 加载帖子 $id 失败: $e');
        }
      }
      if (!ref.mounted || newNodes.isEmpty) return;

      final updated = state.value;
      if (updated == null) return;
      final filtered = newNodes
          .where(
            (node) =>
                updated.opPost?.id != node.post.id &&
                !_containsPostId(updated.roots, node.post.id),
          )
          .toList();
      if (filtered.isEmpty) return;

      state = AsyncValue.data(
        updated.copyWith(roots: [...filtered, ...updated.roots]),
      );
    } catch (e) {
      debugPrint('[NestedTopic] loadNewRoots failed: $e');
    }
  }

  /// 清除已消费的子回复创建事件。
  void clearLastChildCreated() {
    final current = state.value;
    if (current == null || current.lastChildCreated == null) return;
    state = AsyncValue.data(current.copyWith(clearLastChildCreated: true));
  }

  bool _containsPostId(List<NestedNode> nodes, int postId) {
    for (final node in nodes) {
      if (node.post.id == postId) return true;
      if (_containsPostId(node.children, postId)) return true;
    }
    return false;
  }
}

final nestedTopicProvider = AsyncNotifierProvider.family
    .autoDispose<NestedTopicNotifier, NestedTopicState, NestedTopicParams>(
      NestedTopicNotifier.new,
    );
