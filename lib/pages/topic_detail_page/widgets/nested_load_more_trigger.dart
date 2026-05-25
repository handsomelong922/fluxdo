/// 树形视图加载更多的滚动触发护栏。
///
/// 首次进入底部区域只进入待触发状态，用户继续向底部滚动一小段后才触发，
/// 避免页面初次布局或跳转到底部时立刻请求下一页。
class NestedLoadMoreTrigger {
  final double triggerDistance;
  final double minForwardDelta;

  bool _armed = false;
  double? _lastPixels;

  NestedLoadMoreTrigger({this.triggerDistance = 360, this.minForwardDelta = 4});

  bool get isArmed => _armed;

  void reset() {
    _armed = false;
    _lastPixels = null;
  }

  bool update({
    required double pixels,
    required double maxScrollExtent,
    required bool hasMoreRoots,
    required bool isLoadingMore,
  }) {
    final previousPixels = _lastPixels;
    final scrollingTowardBottom =
        previousPixels != null && pixels > previousPixels + minForwardDelta;
    _lastPixels = pixels;

    if (!hasMoreRoots || isLoadingMore) {
      _armed = false;
      return false;
    }

    final nearLoadMore = pixels >= maxScrollExtent - triggerDistance;
    if (!nearLoadMore) {
      _armed = false;
      return false;
    }

    if (!_armed) {
      _armed = true;
      return false;
    }

    if (scrollingTowardBottom) {
      _armed = false;
      return true;
    }

    return false;
  }
}
