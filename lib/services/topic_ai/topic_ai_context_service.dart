import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/topic.dart';
import '../../providers/core_providers.dart';

typedef TopicAiPostsFetcher =
    Future<PostStream> Function(int topicId, List<int> postIds);

class TopicAiContextPost {
  final int postId;
  final int postNumber;
  final String username;
  final String cooked;

  const TopicAiContextPost({
    required this.postId,
    required this.postNumber,
    required this.username,
    required this.cooked,
  });

  factory TopicAiContextPost.fromPost(Post post) {
    return TopicAiContextPost(
      postId: post.id,
      postNumber: post.postNumber,
      username: post.username,
      cooked: post.cooked,
    );
  }

  TopicPostContext toTopicPostContext() {
    return TopicPostContext(
      postNumber: postNumber,
      username: username,
      cooked: cooked,
    );
  }
}

class TopicAiContextService {
  const TopicAiContextService();

  int postCountForScope(ContextScope scope, int total) {
    return switch (scope) {
      ContextScope.firstPostOnly => total <= 0 ? 0 : 1,
      ContextScope.first5 => total.clamp(0, 5),
      ContextScope.first10 => total.clamp(0, 10),
      ContextScope.first20 => total.clamp(0, 20),
      ContextScope.all => total,
    };
  }

  Future<List<TopicAiContextPost>> loadContextPosts({
    required int topicId,
    required TopicDetail detail,
    required ContextScope scope,
    required TopicAiPostsFetcher fetchPosts,
    List<TopicAiContextPost> cachedPosts = const [],
  }) async {
    final neededCount = postCountForScope(
      scope,
      detail.postStream.stream.length,
    );
    if (neededCount <= 0) {
      return const [];
    }

    final neededIds = detail.postStream.stream.take(neededCount).toList();
    final cachedMap = {for (final post in cachedPosts) post.postId: post};
    final loadedMap = {
      for (final post in detail.postStream.posts)
        post.id: TopicAiContextPost.fromPost(post),
    };

    final orderedPosts = <TopicAiContextPost>[];
    final missingIds = <int>[];

    for (final postId in neededIds) {
      final cached = cachedMap[postId];
      if (cached != null) {
        orderedPosts.add(cached);
        continue;
      }

      final loaded = loadedMap[postId];
      if (loaded != null) {
        orderedPosts.add(loaded);
        continue;
      }

      missingIds.add(postId);
    }

    if (missingIds.isEmpty) {
      orderedPosts.sort((a, b) => a.postNumber.compareTo(b.postNumber));
      return orderedPosts;
    }

    final fetchedMap = <int, TopicAiContextPost>{};
    for (var i = 0; i < missingIds.length; i += 20) {
      final batch = missingIds.sublist(i, (i + 20).clamp(0, missingIds.length));
      final postStream = await fetchPosts(topicId, batch);
      for (final post in postStream.posts) {
        fetchedMap[post.id] = TopicAiContextPost.fromPost(post);
      }
    }

    for (final postId in missingIds) {
      final fetched = fetchedMap[postId];
      if (fetched != null) {
        orderedPosts.add(fetched);
      }
    }

    orderedPosts.sort((a, b) => a.postNumber.compareTo(b.postNumber));
    return orderedPosts;
  }
}

final topicAiContextServiceProvider = Provider<TopicAiContextService>((ref) {
  return const TopicAiContextService();
});

final topicAiPostsFetcherProvider = Provider<TopicAiPostsFetcher>((ref) {
  final discourseService = ref.watch(discourseServiceProvider);
  return discourseService.getPosts;
});
