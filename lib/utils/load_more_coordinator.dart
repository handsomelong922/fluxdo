import 'dart:async';

import 'topic_keyword_filter.dart';

typedef LoadMoreAction = Future<void> Function();
typedef BoolReader = bool Function();
typedef CountReader = FutureOr<int> Function();
typedef AutoLoadMoreDecider = bool Function(LoadMoreAttempt attempt);
typedef CooldownDecider = bool Function(LoadMoreAttempt attempt);

class LoadMoreAttempt {
  const LoadMoreAttempt({
    required this.before,
    required this.after,
    required this.attempts,
    required this.hasMore,
  });

  final int before;
  final int after;
  final int attempts;
  final bool hasMore;

  int get delta => after - before;
}

/// Coordinates near-bottom pagination triggers.
///
/// It keeps scroll listeners thin while centralizing three guardrails:
/// no concurrent load-more runs, optional bounded auto-continuation, and a
/// cooldown while a list remains stuck near the bottom.
class LoadMoreCoordinator {
  LoadMoreCoordinator({
    this.triggerDistance = 200,
    this.releaseDistance = 200,
    this.onRunningChanged,
  });

  final double triggerDistance;
  final double releaseDistance;

  /// 包含请求、异步过滤和自动续页，避免页脚在中间阶段闪回空闲。
  final void Function(bool isRunning)? onRunningChanged;

  bool _isRunning = false;
  bool _isCoolingDown = false;

  bool get isRunning => _isRunning;
  bool get isCoolingDown => _isCoolingDown;

  bool shouldTriggerForDistance(
    double distanceToEnd, {
    double? prefetchDistance,
  }) {
    // 首页按视口预取时，冷却解除与触发必须使用同一边界。
    final release = prefetchDistance ?? releaseDistance;
    final trigger = prefetchDistance ?? triggerDistance;
    if (distanceToEnd >= release) {
      _isCoolingDown = false;
      return false;
    }
    if (_isCoolingDown) return false;
    return distanceToEnd < trigger;
  }

  void resetCooldown() {
    _isCoolingDown = false;
  }

  Future<void> loadMore({
    required LoadMoreAction loadMore,
    required BoolReader hasMore,
    required BoolReader isActive,
    CountReader? progressCount,
    AutoLoadMoreDecider? shouldAutoLoadMore,
    CooldownDecider? shouldCooldown,
  }) async {
    if (_isRunning || _isCoolingDown || !hasMore()) return;

    _isRunning = true;
    try {
      onRunningChanged?.call(true);
      if (shouldAutoLoadMore == null) {
        final before = await progressCount?.call();
        if (!isActive() || (before != null && before < 0)) return;
        await loadMore();
        if (!isActive()) return;
        final after = await progressCount?.call();
        if (!isActive() || (after != null && after < 0)) return;
        if (before != null && after != null) {
          final attempt = LoadMoreAttempt(
            before: before,
            after: after,
            attempts: 0,
            hasMore: hasMore(),
          );
          final cooldown =
              shouldCooldown?.call(attempt) ??
              (attempt.hasMore && attempt.delta <= 0);
          if (cooldown) {
            _isCoolingDown = true;
          }
        }
        return;
      }

      final count = progressCount;
      if (count == null) {
        await loadMore();
        return;
      }

      var attempts = 0;
      while (true) {
        final before = await count();
        if (!isActive() || before < 0) return;
        await loadMore();
        if (!isActive()) return;
        final after = await count();
        if (!isActive() || after < 0) return;
        final attempt = LoadMoreAttempt(
          before: before,
          after: after,
          attempts: attempts,
          hasMore: hasMore(),
        );

        if (!shouldAutoLoadMore(attempt)) {
          if (shouldCooldown?.call(attempt) ?? false) {
            _isCoolingDown = true;
          }
          break;
        }
        attempts++;
      }
    } finally {
      _isRunning = false;
      onRunningChanged?.call(false);
    }
  }
}

class TopicLoadMoreCoordinator extends LoadMoreCoordinator {
  TopicLoadMoreCoordinator({
    super.triggerDistance,
    super.releaseDistance,
    super.onRunningChanged,
  });

  Future<void> loadTopicPage({
    required LoadMoreAction loadMore,
    required BoolReader hasMore,
    required BoolReader isActive,
    required CountReader itemCount,
    CountReader? visibleItemCount,
    required bool hasKeywordFilter,
  }) {
    if (!hasKeywordFilter) {
      return super.loadMore(
        loadMore: loadMore,
        hasMore: hasMore,
        isActive: isActive,
        progressCount: itemCount,
      );
    }

    return super.loadMore(
      loadMore: loadMore,
      hasMore: hasMore,
      isActive: isActive,
      progressCount: visibleItemCount ?? itemCount,
      shouldAutoLoadMore: (attempt) => TopicKeywordFilter.shouldAutoLoadMore(
        visibleBefore: attempt.before,
        visibleAfter: attempt.after,
        hasMore: attempt.hasMore,
        attempts: attempt.attempts,
      ),
      shouldCooldown: (attempt) =>
          attempt.hasMore &&
          attempt.attempts >= TopicKeywordFilter.autoLoadMaxAttempts &&
          attempt.delta < TopicKeywordFilter.autoLoadVisibleThreshold,
    );
  }
}
