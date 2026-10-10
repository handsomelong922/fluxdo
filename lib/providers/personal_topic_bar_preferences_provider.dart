import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_provider.dart';

/// 枚举顺序同时作为初始顺序；持久化使用名称，避免枚举索引变化。
enum TopicBarAction { scrollToTop, filter, share, bookmark }

const topicBarOrderPreferenceKey = 'pref_personal_topic_bar_order';

List<TopicBarAction> normalizeTopicBarOrder(Iterable<String> names) {
  final result = <TopicBarAction>[];
  for (final name in names) {
    for (final action in TopicBarAction.values) {
      if (action.name == name && !result.contains(action)) result.add(action);
    }
  }
  for (final action in TopicBarAction.values) {
    if (!result.contains(action)) result.add(action);
  }
  return List.unmodifiable(result);
}

final personalTopicBarPreferencesProvider =
    NotifierProvider<PersonalTopicBarPreferences, List<TopicBarAction>>(
      PersonalTopicBarPreferences.new,
    );

class PersonalTopicBarPreferences extends Notifier<List<TopicBarAction>> {
  @override
  List<TopicBarAction> build() {
    final stored = ref
        .watch(sharedPreferencesProvider)
        .get(topicBarOrderPreferenceKey);
    return normalizeTopicBarOrder(
      stored is List ? stored.whereType<String>() : const [],
    );
  }

  Future<void> setOrder(Iterable<TopicBarAction> order) async {
    final normalized = normalizeTopicBarOrder(
      order.map((action) => action.name),
    );
    state = normalized;
    await ref
        .read(sharedPreferencesProvider)
        .setStringList(
          topicBarOrderPreferenceKey,
          normalized.map((action) => action.name).toList(),
        );
  }

  Future<void> reset() => setOrder(TopicBarAction.values);
}
