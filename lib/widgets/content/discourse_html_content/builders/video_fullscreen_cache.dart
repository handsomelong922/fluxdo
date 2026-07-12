import 'package:flutter/widgets.dart';

class FullscreenVideoCacheEntry<TVideo, TController> {
  const FullscreenVideoCacheEntry({
    required this.video,
    required this.controller,
    required this.chewieKey,
  });

  final TVideo video;
  final TController controller;
  final GlobalKey chewieKey;
}

/// 全屏视频控制器的短生命周期缓存。
///
/// [peek] 始终是只读操作：系统全屏动画可能连续触发多轮窗口尺寸变化，
/// 缓存必须一直保留到 Chewie 明确退出全屏后再由 [remove] 清理。
class FullscreenVideoCache<TVideo, TController> {
  final Map<String, FullscreenVideoCacheEntry<TVideo, TController>> _entries =
      <String, FullscreenVideoCacheEntry<TVideo, TController>>{};

  int get length => _entries.length;

  void store({
    required String url,
    required TVideo video,
    required TController controller,
    required GlobalKey chewieKey,
  }) {
    _entries[url] = FullscreenVideoCacheEntry<TVideo, TController>(
      video: video,
      controller: controller,
      chewieKey: chewieKey,
    );
  }

  FullscreenVideoCacheEntry<TVideo, TController>? peek(String url) {
    return _entries[url];
  }

  FullscreenVideoCacheEntry<TVideo, TController>? remove(String url) {
    return _entries.remove(url);
  }
}

bool shouldKeepFullscreenVideoAlive({
  required bool didLockLayout,
  required bool pendingLockRelease,
}) {
  return didLockLayout || pendingLockRelease;
}
