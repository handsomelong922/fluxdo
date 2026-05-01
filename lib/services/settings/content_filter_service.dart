// CUSTOM: Tag Filter
// CUSTOM: User Filter
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/topic.dart';
import '../../providers/theme_provider.dart';

class ContentFilterState {
  final List<String> blockedTags;
  final List<String> blockedUsers;

  const ContentFilterState({
    this.blockedTags = const <String>[],
    this.blockedUsers = const <String>[],
  });

  bool get hasBlockedTags => blockedTags.isNotEmpty;
  bool get hasBlockedUsers => blockedUsers.isNotEmpty;

  ContentFilterState copyWith({
    List<String>? blockedTags,
    List<String>? blockedUsers,
  }) {
    return ContentFilterState(
      blockedTags: blockedTags ?? this.blockedTags,
      blockedUsers: blockedUsers ?? this.blockedUsers,
    );
  }
}

class ContentFilterNotifier extends StateNotifier<ContentFilterState> {
  // CUSTOM: Tag Filter
  static const String blockedTagsKey = 'custom_blocked_tags';

  // CUSTOM: User Filter
  static const String blockedUsersKey = 'custom_blocked_users';

  final SharedPreferences _prefs;

  ContentFilterNotifier(this._prefs) : super(_load(_prefs));

  static ContentFilterState _load(SharedPreferences prefs) {
    return ContentFilterState(
      blockedTags: prefs.getStringList(blockedTagsKey) ?? const <String>[],
      blockedUsers: prefs.getStringList(blockedUsersKey) ?? const <String>[],
    );
  }

  static List<String> normalizeCommaSeparated(String raw) {
    final result = <String>[];
    final seen = <String>{};

    for (final item in raw.split(',')) {
      final trimmed = item.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      if (seen.add(key)) {
        result.add(trimmed);
      }
    }

    return result;
  }

  void setBlockedTagsFromInput(String raw) {
    final nextTags = normalizeCommaSeparated(raw);
    state = state.copyWith(blockedTags: nextTags);
    _prefs.setStringList(blockedTagsKey, nextTags);
  }

  void setBlockedUsersFromInput(String raw) {
    final nextUsers = normalizeCommaSeparated(raw);
    state = state.copyWith(blockedUsers: nextUsers);
    _prefs.setStringList(blockedUsersKey, nextUsers);
  }

  void clearBlockedTags() {
    state = state.copyWith(blockedTags: const <String>[]);
    _prefs.remove(blockedTagsKey);
  }

  void clearBlockedUsers() {
    state = state.copyWith(blockedUsers: const <String>[]);
    _prefs.remove(blockedUsersKey);
  }

  bool matchesTagName(String? tagName) {
    if (tagName == null || tagName.isEmpty || !state.hasBlockedTags) {
      return false;
    }
    final target = tagName.toLowerCase();
    return state.blockedTags.any((tag) => tag.toLowerCase() == target);
  }

  bool matchesAnyTag(Iterable<Tag> tags) {
    if (!state.hasBlockedTags) return false;
    for (final tag in tags) {
      if (matchesTagName(tag.name)) return true;
    }
    return false;
  }

  bool matchesUsername(String? username) {
    if (username == null || username.isEmpty || !state.hasBlockedUsers) {
      return false;
    }
    final target = username.toLowerCase();
    return state.blockedUsers.any((user) => user.toLowerCase() == target);
  }

  String? topicAuthorUsername(Topic topic) {
    if (topic.posters.isNotEmpty) {
      final username = topic.posters.first.user?.username;
      if (username != null && username.isNotEmpty) {
        return username;
      }
    }
    return null;
  }

  bool matchesTopic(Topic topic) {
    if (matchesAnyTag(topic.tags)) return true;
    return matchesUsername(topicAuthorUsername(topic));
  }

  TopicDetail applyUserFilterToDetail(TopicDetail detail) {
    if (!state.hasBlockedUsers) return detail;

    final originalPosts = detail.postStream.posts;
    if (originalPosts.isEmpty) return detail;

    final filteredPosts = <Post>[];
    final hiddenBuffer = <int>[];
    final before = <int, List<int>>{};
    final after = <int, List<int>>{};

    void addBefore(int postId, List<int> ids) {
      if (ids.isEmpty) return;
      before.update(
        postId,
        (existing) => [...existing, ...ids],
        ifAbsent: () => [...ids],
      );
    }

    void addAfter(int postId, List<int> ids) {
      if (ids.isEmpty) return;
      after.update(
        postId,
        (existing) => [...existing, ...ids],
        ifAbsent: () => [...ids],
      );
    }

    for (final post in originalPosts) {
      final shouldHide = post.postNumber != 1 && matchesUsername(post.username);
      if (shouldHide) {
        hiddenBuffer.add(post.id);
        continue;
      }

      if (hiddenBuffer.isNotEmpty) {
        addBefore(post.id, List<int>.from(hiddenBuffer));
        hiddenBuffer.clear();
      }
      filteredPosts.add(post);
    }

    if (filteredPosts.isEmpty) {
      return detail;
    }

    if (hiddenBuffer.isNotEmpty) {
      addAfter(filteredPosts.last.id, List<int>.from(hiddenBuffer));
      hiddenBuffer.clear();
    }

    final existingGaps = detail.postStream.gaps;
    if (existingGaps != null) {
      for (final entry in existingGaps.before.entries) {
        addBefore(entry.key, entry.value);
      }
      for (final entry in existingGaps.after.entries) {
        addAfter(entry.key, entry.value);
      }
    }

    final dedupedBefore = <int, List<int>>{};
    for (final entry in before.entries) {
      dedupedBefore[entry.key] = _dedupeIds(entry.value);
    }
    final dedupedAfter = <int, List<int>>{};
    for (final entry in after.entries) {
      dedupedAfter[entry.key] = _dedupeIds(entry.value);
    }

    final mergedGaps = PostStreamGaps(
      before: dedupedBefore,
      after: dedupedAfter,
    );

    return detail.copyWith(
      postStream: PostStream(
        posts: filteredPosts,
        stream: detail.postStream.stream,
        gaps: mergedGaps.isEmpty ? null : mergedGaps,
      ),
    );
  }

  static List<int> _dedupeIds(List<int> ids) {
    final result = <int>[];
    final seen = <int>{};
    for (final id in ids) {
      if (seen.add(id)) {
        result.add(id);
      }
    }
    return result;
  }
}

final contentFilterProvider =
    StateNotifierProvider<ContentFilterNotifier, ContentFilterState>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider);
      return ContentFilterNotifier(prefs);
    });
