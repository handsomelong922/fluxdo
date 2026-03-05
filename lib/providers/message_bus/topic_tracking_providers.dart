import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/message_bus_service.dart';
import '../../services/preloaded_data_service.dart';
import '../../services/background/ios_background_fetch.dart';
import '../discourse_providers.dart';
import 'message_bus_service_provider.dart';

/// 话题追踪状态元数据 Provider（MessageBus 频道初始 message ID）
final topicTrackingStateMetaProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final service = ref.watch(discourseServiceProvider);
  return service.getPreloadedTopicTrackingMeta();
});

/// MessageBus 初始化 Notifier
/// 统一管理所有频道的批量订阅，避免串行等待
class MessageBusInitNotifier extends Notifier<void> {
  final Map<String, MessageBusCallback> _allCallbacks = {};
  
  @override
  void build() {
    final messageBus = ref.watch(messageBusServiceProvider);
    final currentUser = ref.watch(currentUserProvider).value;
    final metaAsync = ref.watch(topicTrackingStateMetaProvider);
    
    // 清理之前的订阅
    if (_allCallbacks.isNotEmpty) {
      debugPrint('[MessageBusInit] 清理旧订阅: ${_allCallbacks.keys}');
      for (final entry in _allCallbacks.entries) {
        messageBus.unsubscribe(entry.key, entry.value);
      }
      _allCallbacks.clear();
    }
    
    if (currentUser == null) {
      debugPrint('[MessageBusInit] 用户未登录，跳过订阅');
      return;
    }

    // 配置 MessageBus 独立域名（从预加载数据获取）
    final preloaded = PreloadedDataService();
    messageBus.configure(
      baseUrl: preloaded.longPollingBaseUrl,
      sharedSessionKey: preloaded.sharedSessionKey,
    );

    // 同步保存到 SharedPreferences 供 iOS 后台任务使用
    saveBackgroundMessageBusConfig(
      longPollingBaseUrl: preloaded.longPollingBaseUrl,
      sharedSessionKey: preloaded.sharedSessionKey,
    );

    final meta = metaAsync.value;
    if (meta == null) {
      debugPrint('[MessageBusInit] topicTrackingStateMeta 未加载');
      return;
    }
    
    // 逐个订阅话题追踪频道
    // 注意: /notification/ 和 /notification-alert/ 频道由专门的
    // NotificationChannelNotifier 和 NotificationAlertChannelNotifier 管理，
    // 此处只负责话题追踪频道
    debugPrint('[MessageBusInit] 订阅 ${meta.length} 个频道: ${meta.keys}');
    for (final entry in meta.entries) {
      final channel = entry.key;
      final messageId = entry.value as int;

      void onTopicTracking(MessageBusMessage message) {
        debugPrint('[TopicTracking] 收到消息: ${message.channel} #${message.messageId}');
        // TODO: 根据频道类型更新对应的话题列表
      }

      _allCallbacks[channel] = onTopicTracking;
      messageBus.subscribeWithMessageId(channel, onTopicTracking, messageId);
    }
    
    ref.onDispose(() {
      debugPrint('[MessageBusInit] 取消所有订阅: ${_allCallbacks.keys}');
      for (final entry in _allCallbacks.entries) {
        messageBus.unsubscribe(entry.key, entry.value);
      }
      _allCallbacks.clear();
    });
  }
}

final messageBusInitProvider = NotifierProvider<MessageBusInitNotifier, void>(
  MessageBusInitNotifier.new,
);

/// 话题列表新消息状态（按分类隔离）
class TopicListIncomingState {
  /// topicId → categoryId 的映射，用于按 tab/分类隔离新话题指示器
  final Map<int, int?> incomingTopics;

  const TopicListIncomingState({this.incomingTopics = const {}});

  bool get hasIncoming => incomingTopics.isNotEmpty;
  int get incomingCount => incomingTopics.length;

  /// 指定分类是否有新话题（null 表示"全部"tab，统计所有分类）
  bool hasIncomingForCategory(int? categoryId) {
    if (categoryId == null) return incomingTopics.isNotEmpty;
    return incomingTopics.values.any((c) => c == categoryId);
  }

  /// 获取指定分类的新话题数量（null 表示"全部"tab）
  int incomingCountForCategory(int? categoryId) {
    if (categoryId == null) return incomingTopics.length;
    return incomingTopics.values.where((c) => c == categoryId).length;
  }

  /// 获取指定分类的 incoming topic IDs（null 表示全部）
  List<int> incomingTopicIdsForCategory(int? categoryId) {
    if (categoryId == null) return incomingTopics.keys.toList();
    return incomingTopics.entries
        .where((e) => e.value == categoryId)
        .map((e) => e.key)
        .toList();
  }
}

/// 话题列表频道监听器（对齐 Discourse 网页版 TopicTrackingState）
///
/// 同时订阅 /latest 和 /new 两个频道：
/// - /latest 频道：message_type="latest"，表示已有话题收到新回复
/// - /new 频道：message_type="new_topic"，表示有新话题创建
///
/// 在 latest 页面中，两种消息都计入 incoming（同一 topic_id 去重）。
/// 与网页版一致，每条消息即时更新计数，不做防抖。
/// MessageBus 的 long polling 已自然做了批次化。
class LatestChannelNotifier extends Notifier<TopicListIncomingState> {

  @override
  TopicListIncomingState build() {
    final messageBus = ref.watch(messageBusServiceProvider);

    // 构建静音分类 ID 集合（对齐网页版 muted_category_ids + indirectly_muted_category_ids）
    // 从分类列表的 notificationLevel 推导，结合本地覆盖实时反映用户修改
    final categoryMap = ref.watch(categoryMapProvider).value ?? {};
    final notifOverrides = ref.watch(categoryNotificationOverridesProvider);
    final mutedCategoryIds = <int>{};
    for (final category in categoryMap.values) {
      // 本地覆盖优先
      final level = notifOverrides[category.id] ?? category.notificationLevel;
      if (level == 0) {
        mutedCategoryIds.add(category.id);
      }
    }

    // 处理 /latest 和 /new 频道消息的统一回调
    void onMessage(MessageBusMessage message) {
      final data = message.data;
      if (data is! Map<String, dynamic>) return;

      final topicId = data['topic_id'] as int?;
      if (topicId == null) return;

      final messageType = data['message_type'] as String?;
      // 仅处理 latest（话题更新）和 new_topic（新话题创建）两种类型
      if (messageType != 'latest' && messageType != 'new_topic') return;

      // 同一 topic_id 去重（与网页版 _addIncoming 一致）
      if (state.incomingTopics.containsKey(topicId)) return;

      // 提取话题分类 ID（用于按 tab 隔离和静音过滤）
      final payload = data['payload'] as Map<String, dynamic>?;
      final topicCategoryId = payload?['category_id'] as int?;

      // 过滤静音分类（对齐网页版 _processChannelPayload 的 muted_category_ids 检查）
      if (topicCategoryId != null && mutedCategoryIds.contains(topicCategoryId)) {
        return;
      }

      debugPrint('[LatestChannel] incoming +1: type=$messageType, topicId=$topicId, category=$topicCategoryId');

      // 即时更新（与网页版一致，无防抖）
      state = TopicListIncomingState(
        incomingTopics: {...state.incomingTopics, topicId: topicCategoryId},
      );
    }

    // 订阅 /latest 频道（话题更新）
    messageBus.subscribe('/latest', onMessage);
    // 订阅 /new 频道（新话题创建）
    messageBus.subscribe('/new', onMessage);

    ref.onDispose(() {
      messageBus.unsubscribe('/latest', onMessage);
      messageBus.unsubscribe('/new', onMessage);
    });

    return const TopicListIncomingState();
  }

  /// 按 topic IDs 清除 incoming（对齐网页版 clearIncoming）
  void clearIncoming(List<int> topicIds) {
    final toRemove = topicIds.toSet();
    final remaining = Map<int, int?>.from(state.incomingTopics)
      ..removeWhere((id, _) => toRemove.contains(id));
    if (remaining.length == state.incomingTopics.length) return;
    state = TopicListIncomingState(incomingTopics: remaining);
  }

  /// 清除指定分类的新话题标记（null 表示清除全部）
  void clearNewTopicsForCategory(int? categoryId) {
    if (categoryId == null) {
      state = const TopicListIncomingState();
    } else {
      final remaining = Map<int, int?>.from(state.incomingTopics)
        ..removeWhere((_, c) => c == categoryId);
      state = TopicListIncomingState(incomingTopics: remaining);
    }
  }
}

final latestChannelProvider = NotifierProvider<LatestChannelNotifier, TopicListIncomingState>(() {
  return LatestChannelNotifier();
});
