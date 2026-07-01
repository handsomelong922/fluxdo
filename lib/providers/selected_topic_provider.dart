// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../models/topic.dart';

/// 当前选中的话题（用于 Master-Detail 模式）
class SelectedTopicState {
  const SelectedTopicState({
    this.topicId,
    this.initialTitle,
    this.scrollToPostNumber,
    this.instanceId,
    this.initialTopicPreview,
    this.initialFirstPostHtml,
  });

  final int? topicId;
  final String? initialTitle;
  final int? scrollToPostNumber;

  /// provider 实例 ID，用于布局切换时复用同一个 provider
  final String? instanceId;
  final Topic? initialTopicPreview;
  final String? initialFirstPostHtml;

  bool get hasSelection => topicId != null;

  SelectedTopicState copyWith({
    int? topicId,
    String? initialTitle,
    int? scrollToPostNumber,
    String? instanceId,
    Topic? initialTopicPreview,
    String? initialFirstPostHtml,
    bool clearSelection = false,
  }) {
    if (clearSelection) {
      return const SelectedTopicState();
    }
    return SelectedTopicState(
      topicId: topicId ?? this.topicId,
      initialTitle: initialTitle ?? this.initialTitle,
      scrollToPostNumber: scrollToPostNumber ?? this.scrollToPostNumber,
      instanceId: instanceId ?? this.instanceId,
      initialTopicPreview: initialTopicPreview ?? this.initialTopicPreview,
      initialFirstPostHtml: initialFirstPostHtml ?? this.initialFirstPostHtml,
    );
  }
}

class SelectedTopicNotifier extends StateNotifier<SelectedTopicState> {
  SelectedTopicNotifier() : super(const SelectedTopicState());

  void select({
    required int topicId,
    String? initialTitle,
    int? scrollToPostNumber,
    String? instanceId,
    Topic? initialTopicPreview,
    String? initialFirstPostHtml,
  }) {
    state = SelectedTopicState(
      topicId: topicId,
      initialTitle: initialTitle,
      scrollToPostNumber: scrollToPostNumber,
      instanceId: instanceId,
      initialTopicPreview: initialTopicPreview,
      initialFirstPostHtml: initialFirstPostHtml,
    );
  }

  void clear() {
    state = const SelectedTopicState();
  }
}

final selectedTopicProvider =
    StateNotifierProvider<SelectedTopicNotifier, SelectedTopicState>((ref) {
      return SelectedTopicNotifier();
    });

/// 嵌入式详情页的当前浏览位置（按 topicId 索引）
/// 用于布局切换时恢复滚动位置
final detailScrollPositionProvider = StateProvider.family<int?, int>(
  (ref, topicId) => null,
);
