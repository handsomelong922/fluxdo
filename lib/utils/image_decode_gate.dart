import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// 限制 Flutter 标准图片首帧解码的并发数。
///
/// 缓存命中不会创建 codec；动图后续帧也不过闸门。AVIF、
/// 贴纸和 native animated provider 的自有解码管线不经过此入口。
class ImageDecodeGate {
  ImageDecodeGate({int maxInFlight = 2})
    : _maxInFlight = maxInFlight,
      assert(maxInFlight > 0);

  static final ImageDecodeGate global = ImageDecodeGate();

  final int _maxInFlight;
  final Queue<Completer<void>> _waiters = Queue();
  int _inFlight = 0;

  Future<void> _acquire() {
    if (_inFlight < _maxInFlight) {
      _inFlight++;
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _waiters.addLast(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      // 令牌直接交给队头，in-flight 数不变。
      _waiters.removeFirst().complete();
      return;
    }
    _inFlight--;
  }

  Future<T> run<T>(Future<T> Function() task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }

  @visibleForTesting
  int get inFlight => _inFlight;

  @visibleForTesting
  int get waitingCount => _waiters.length;
}

/// 只对第一帧 `getNextFrame()` 限流的 codec 包装。
class GatedImageCodec implements ui.Codec {
  GatedImageCodec(this._inner, {ImageDecodeGate? gate})
    : _gate = gate ?? ImageDecodeGate.global;

  final ui.Codec _inner;
  final ImageDecodeGate _gate;
  bool _firstFrameRequested = false;
  bool _disposed = false;

  @override
  int get frameCount => _inner.frameCount;

  @override
  int get repetitionCount => _inner.repetitionCount;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _inner.dispose();
  }

  @override
  Future<ui.FrameInfo> getNextFrame() {
    if (_firstFrameRequested) return _inner.getNextFrame();
    _firstFrameRequested = true;
    return _gate.run(() {
      // 排队期间图片可能已滚出视口，框架因无 listener
      // 而 dispose codec。出队后不再访问已释放的 native peer。
      if (_disposed) {
        throw StateError('GatedImageCodec was disposed while queued');
      }
      return _inner.getNextFrame();
    });
  }
}

/// 应用 binding：仅在标准图片解码入口包装 codec。
class FluxdoWidgetsBinding extends WidgetsFlutterBinding {
  static FluxdoWidgetsBinding? _instance;

  static FluxdoWidgetsBinding ensureInitialized() =>
      _instance ??= FluxdoWidgetsBinding();

  @override
  Future<ui.Codec> instantiateImageCodecWithSize(
    ui.ImmutableBuffer buffer, {
    ui.TargetImageSizeCallback? getTargetSize,
  }) async {
    final codec = await super.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: getTargetSize,
    );
    return GatedImageCodec(codec);
  }
}
