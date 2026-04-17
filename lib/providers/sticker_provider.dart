import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../models/sticker.dart';
import '../services/sticker_market_service.dart';
import 'theme_provider.dart'; // sharedPreferencesProvider

/// 表情包市场服务 Provider
final stickerMarketServiceProvider = Provider<StickerMarketService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return StickerMarketService(prefs);
});

/// 市场全部非归档分组
final stickerGroupsProvider = FutureProvider<List<StickerGroup>>((ref) async {
  final service = ref.watch(stickerMarketServiceProvider);
  return service.getAllGroups();
});

/// 分组详情（按 groupId 懒加载）
final stickerGroupDetailProvider =
    FutureProvider.family<StickerGroupDetail, String>((ref, groupId) async {
      final service = ref.watch(stickerMarketServiceProvider);
      return service.getGroupDetail(groupId);
    });

/// 市场分组分页加载（供市场浏览面板使用）
final marketGroupsProvider =
    StateNotifierProvider.autoDispose<
      MarketGroupsNotifier,
      AsyncValue<List<StickerGroup>>
    >((ref) {
      final service = ref.watch(stickerMarketServiceProvider);
      return MarketGroupsNotifier(service);
    });

class MarketGroupsNotifier
    extends StateNotifier<AsyncValue<List<StickerGroup>>> {
  final StickerMarketService _service;
  int _loadedPages = 0;
  int _totalPages = 0;
  bool _isLoadingMore = false;

  MarketGroupsNotifier(this._service) : super(const AsyncValue.loading()) {
    _loadFirstPage();
  }

  bool get hasMore => _loadedPages < _totalPages;

  Future<void> _loadFirstPage() async {
    try {
      // 并行请求索引和第一页
      final results = await Future.wait([
        _service.getIndex(),
        _service.getGroupsPage(1),
      ]);
      _totalPages = (results[0] as StickerMarketIndex).totalPages;
      _loadedPages = 1;
      state = AsyncValue.data(results[1] as List<StickerGroup>);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !hasMore || state is! AsyncData) return;
    _isLoadingMore = true;
    try {
      final nextPage = _loadedPages + 1;
      final newGroups = await _service.getGroupsPage(nextPage);
      _loadedPages = nextPage;
      if (!mounted) return;

      // 单次提交新页面，避免滚动过程中连续多次 rebuild 整个列表。
      state = AsyncValue.data([...state.value!, ...newGroups]);
    } catch (e) {
      debugPrint('[MarketGroups] 加载第${_loadedPages + 1}页失败: $e');
    } finally {
      _isLoadingMore = false;
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    _loadedPages = 0;
    _totalPages = 0;
    await _loadFirstPage();
  }
}

/// 已订阅的分组 ID 列表（响应式）
final subscribedStickerIdsProvider =
    StateNotifierProvider<SubscribedStickerIdsNotifier, List<String>>((ref) {
      final service = ref.watch(stickerMarketServiceProvider);
      return SubscribedStickerIdsNotifier(service);
    });

class SubscribedStickerIdsNotifier extends StateNotifier<List<String>> {
  final StickerMarketService _service;

  SubscribedStickerIdsNotifier(this._service)
    : super(_service.getSubscribedGroupIds());

  Future<void> subscribe(String groupId) async {
    await _service.subscribe(groupId);
    state = _service.getSubscribedGroupIds();
  }

  Future<void> unsubscribe(String groupId) async {
    await _service.unsubscribe(groupId);
    state = _service.getSubscribedGroupIds();
  }

  bool isSubscribed(String groupId) => state.contains(groupId);
}

/// 最近使用的表情包（响应式）
final recentStickersProvider =
    StateNotifierProvider<RecentStickersNotifier, List<StickerItem>>((ref) {
      final service = ref.watch(stickerMarketServiceProvider);
      return RecentStickersNotifier(service);
    });

class RecentStickersNotifier extends StateNotifier<List<StickerItem>> {
  final StickerMarketService _service;

  RecentStickersNotifier(this._service) : super(_service.getRecentStickers());

  Future<void> add(StickerItem sticker) async {
    await _service.addRecentSticker(sticker);
    state = _service.getRecentStickers();
  }
}
