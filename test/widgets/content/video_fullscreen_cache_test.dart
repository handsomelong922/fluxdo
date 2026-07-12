import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/content/discourse_html_content/builders/video_fullscreen_cache.dart';

void main() {
  test('全屏缓存允许连续只读复用并保留同一个 Chewie key', () {
    final cache = FullscreenVideoCache<Object, Object>();
    final video = Object();
    final controller = Object();
    final chewieKey = GlobalKey(debugLabel: 'chewie');

    cache.store(
      url: 'https://example.com/video.mp4',
      video: video,
      controller: controller,
      chewieKey: chewieKey,
    );

    final first = cache.peek('https://example.com/video.mp4');
    final second = cache.peek('https://example.com/video.mp4');

    expect(first, isNotNull);
    expect(identical(first?.video, video), isTrue);
    expect(identical(first?.controller, controller), isTrue);
    expect(identical(first?.chewieKey, chewieKey), isTrue);
    expect(identical(second, first), isTrue);
    expect(cache.length, 1);
  });

  test('退出全屏时显式移除缓存', () {
    final cache = FullscreenVideoCache<Object, Object>();
    cache.store(
      url: 'video',
      video: Object(),
      controller: Object(),
      chewieKey: GlobalKey(),
    );

    expect(cache.remove('video'), isNotNull);
    expect(cache.peek('video'), isNull);
    expect(cache.length, 0);
  });

  test('只在全屏和退出恢复窗口请求 keepalive', () {
    expect(
      shouldKeepFullscreenVideoAlive(
        didLockLayout: false,
        pendingLockRelease: false,
      ),
      isFalse,
    );
    expect(
      shouldKeepFullscreenVideoAlive(
        didLockLayout: true,
        pendingLockRelease: false,
      ),
      isTrue,
    );
    expect(
      shouldKeepFullscreenVideoAlive(
        didLockLayout: false,
        pendingLockRelease: true,
      ),
      isTrue,
    );
  });
}
