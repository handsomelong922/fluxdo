// CUSTOM: Tag Filter
// CUSTOM: User Filter
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/topic.dart';
import '../../providers/theme_provider.dart';

const _filteredPostPlaceholderHtml = '<p>内容已被用户屏蔽规则隐藏</p>';

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

  static String? normalizeSingleValue(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  bool _containsIgnoreCase(Iterable<String> values, String target) {
    final normalizedTarget = target.toLowerCase();
    return values.any((value) => value.toLowerCase() == normalizedTarget);
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

  Future<bool> addBlockedUser(String username) async {
    final normalized = normalizeSingleValue(username);
    if (normalized == null || _containsIgnoreCase(state.blockedUsers, normalized)) {
      return false;
    }

    final nextUsers = [...state.blockedUsers, normalized];
    state = state.copyWith(blockedUsers: nextUsers);
    await _prefs.setStringList(blockedUsersKey, nextUsers);
    return true;
  }

  Future<bool> removeBlockedUser(String username) async {
    final normalized = normalizeSingleValue(username);
    if (normalized == null) return false;

    final nextUsers = state.blockedUsers
        .where((user) => user.toLowerCase() != normalized.toLowerCase())
        .toList();
    if (nextUsers.length == state.blockedUsers.length) {
      return false;
    }

    state = state.copyWith(blockedUsers: nextUsers);
    if (nextUsers.isEmpty) {
      await _prefs.remove(blockedUsersKey);
    } else {
      await _prefs.setStringList(blockedUsersKey, nextUsers);
    }
    return true;
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
      if (matchesTagName(tag.name) || matchesTagName(tag.slug)) return true;
    }
    return false;
  }

  bool matchesUsername(String? username) {
    if (username == null || username.isEmpty || !state.hasBlockedUsers) {
      return false;
    }
    final target = username.toLowerCase();
    return _containsIgnoreCase(state.blockedUsers, target);
  }

  Post applyUserFilterToPost(Post post) {
    if (!matchesUsername(post.username)) {
      return post;
    }
    // CUSTOM: User Filter - never reveal filtered posts in detail view
    return post.copyWith(
      cooked: _filteredPostPlaceholderHtml,
      hidden: true,
      cookedHidden: false,
      canSeeHiddenPost: false,
    );
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

    bool changed = false;
    final filteredPosts = originalPosts.map((post) {
      final filteredPost = applyUserFilterToPost(post);
      if (filteredPost != post) {
        changed = true;
      }
      return filteredPost;
    }).toList();

    if (!changed) return detail;

    return detail.copyWith(
      postStream: PostStream(
        posts: filteredPosts,
        stream: detail.postStream.stream,
        gaps: detail.postStream.gaps,
      ),
    );
  }
}

final contentFilterProvider =
    StateNotifierProvider<ContentFilterNotifier, ContentFilterState>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider);
      return ContentFilterNotifier(prefs);
    });
