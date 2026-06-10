import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_avif/flutter_avif.dart' as fa;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:native_animated_image/native_animated_image.dart'
    show NativeAnimatedImageException, NativeAnimatedImageFfi;

import 'discourse_cache_manager.dart';

const int _kErrUnsupported = -2;

bool _bytesLookLikeAvif(Uint8List bytes) {
  if (bytes.length < 12) return false;
  if (bytes[4] != 0x66 ||
      bytes[5] != 0x74 ||
      bytes[6] != 0x79 ||
      bytes[7] != 0x70) {
    return false;
  }
  final b8 = bytes[8], b9 = bytes[9], b10 = bytes[10], b11 = bytes[11];
  if (b8 == 0x61 && b9 == 0x76 && b10 == 0x69 && b11 == 0x66) return true;
  if (b8 == 0x61 && b9 == 0x76 && b10 == 0x69 && b11 == 0x73) return true;
  if (b8 == 0x6d && b9 == 0x69 && b10 == 0x66 && b11 == 0x31) return true;
  if (b8 == 0x6d && b9 == 0x73 && b10 == 0x66 && b11 == 0x31) return true;
  return false;
}

/// sticker 缩略图 Provider：首帧解码、缩放并缓存为 PNG。
///
/// Grid 缩略图只需要第一帧。把 AVIF/GIF/WebP/APNG 统一压成 PNG cache 后，
/// 后续滚动只走 Flutter 内置 PNG codec，可避开大量动图同时解码造成的卡顿。
class StickerThumbnailProvider extends ImageProvider<StickerThumbnailProvider> {
  const StickerThumbnailProvider(
    this.url, {
    required this.targetSize,
    this.scale = 1.0,
    this.cacheManager,
  });

  final String url;
  final int targetSize;
  final double scale;
  final BaseCacheManager? cacheManager;

  static void cancelInflight() {
    _thumbnailGeneration++;
  }

  static bool supports(String url) {
    try {
      final path = Uri.parse(url).path.toLowerCase();
      return path.endsWith('.avif') ||
          path.endsWith('.gif') ||
          path.endsWith('.webp') ||
          path.endsWith('.apng');
    } catch (_) {
      final lower = url.toLowerCase();
      return lower.endsWith('.avif') ||
          lower.endsWith('.gif') ||
          lower.endsWith('.webp') ||
          lower.endsWith('.apng');
    }
  }

  static Future<void> precacheBatch(
    List<String> urls, {
    required int targetSize,
    required BaseCacheManager cacheManager,
    bool Function()? shouldContinue,
  }) async {
    final pendingNonAvif = <(String, Uint8List)>[];
    var skippedAvif = 0;

    for (final url in urls) {
      if (shouldContinue != null && !shouldContinue()) return;
      if (!supports(url)) continue;
      final key = _thumbnailCacheKey(url, targetSize);
      if (_knownThumbnailKeys.contains(key) ||
          _pendingThumbnailTasks.containsKey(key)) {
        continue;
      }
      if (await _readCachedThumbnailBytes(cacheManager, key) != null) continue;

      try {
        final file = await cacheManager.getSingleFile(url);
        final bytes = await file.readAsBytes();
        if (_bytesLookLikeAvif(bytes)) {
          skippedAvif++;
        } else {
          pendingNonAvif.add((url, bytes));
        }
      } catch (e) {
        debugPrint('[StickerThumbnail] fetch failed $url: $e');
      }
    }

    for (final entry in pendingNonAvif) {
      if (shouldContinue != null && !shouldContinue()) return;
      final reply = await _DecoderWorkerPool.instance.decode(entry.$2);
      if (reply == null) continue;
      await _writeThumbnailFromReply(
        url: entry.$1,
        bytes: entry.$2,
        reply: reply,
        targetSize: targetSize,
        cacheManager: cacheManager,
      );
    }

    if (skippedAvif > 0) {
      debugPrint('[StickerThumbnail] skip AVIF batch prefetch: $skippedAvif');
    }
  }

  static Future<void> precache(
    String url, {
    required int targetSize,
    BaseCacheManager? cacheManager,
  }) async {
    if (!supports(url)) return;
    final manager = cacheManager ?? DiscourseCacheManager();
    final key = _thumbnailCacheKey(url, targetSize);
    if (_knownThumbnailKeys.contains(key)) return;
    if (await _readCachedThumbnailBytes(manager, key) != null) return;

    final pending = _pendingThumbnailTasks[key];
    if (pending != null) {
      await pending;
      return;
    }

    final task = _warmThumbnail(
      manager: manager,
      url: url,
      targetSize: targetSize,
      key: key,
    );
    _pendingThumbnailTasks[key] = task;
    try {
      await task;
    } finally {
      _pendingThumbnailTasks.remove(key);
    }
  }

  @override
  Future<StickerThumbnailProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<StickerThumbnailProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    StickerThumbnailProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(_loadThumbnail(key));
  }

  Future<ImageInfo> _loadThumbnail(StickerThumbnailProvider key) async {
    final manager = key.cacheManager ?? DiscourseCacheManager();
    final thumbKey = _thumbnailCacheKey(key.url, key.targetSize);

    final cachedBytes = await _readCachedThumbnailBytes(manager, thumbKey);
    if (cachedBytes != null) {
      return _decodeThumbnailBytes(cachedBytes, key.scale);
    }

    await precache(key.url, targetSize: key.targetSize, cacheManager: manager);
    final warmedBytes = await _readCachedThumbnailBytes(manager, thumbKey);
    if (warmedBytes != null) {
      return _decodeThumbnailBytes(warmedBytes, key.scale);
    }

    final image = await _decodeFirstFrameImage(
      manager: manager,
      url: key.url,
      targetSize: key.targetSize,
    );
    unawaited(_cacheThumbnail(manager, thumbKey, image));
    return ImageInfo(image: image, scale: key.scale);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StickerThumbnailProvider &&
        other.url == url &&
        other.targetSize == targetSize &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(url, targetSize, scale);
}

final _avifSemaphore = _Semaphore(1);
final _nonAvifSemaphore = _Semaphore(8);
final _pendingThumbnailTasks = <String, Future<void>>{};
final _knownThumbnailKeys = <String>{};
int _thumbnailGeneration = 0;

class _ThumbnailCancelled implements Exception {
  const _ThumbnailCancelled();
}

String _thumbnailCacheKey(String url, int targetSize) {
  return 'sticker_thumb:$targetSize:$url';
}

Future<Uint8List?> _readCachedThumbnailBytes(
  BaseCacheManager manager,
  String key,
) async {
  final cached = await manager.getFileFromCache(key);
  if (cached == null) return null;
  _knownThumbnailKeys.add(key);
  return cached.file.readAsBytes();
}

Future<ImageInfo> _decodeThumbnailBytes(Uint8List bytes, double scale) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final codec = await ui.instantiateImageCodecFromBuffer(buffer);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return ImageInfo(image: frame.image, scale: scale);
}

Future<void> _warmThumbnail({
  required BaseCacheManager manager,
  required String url,
  required int targetSize,
  required String key,
}) async {
  ui.Image? image;
  try {
    image = await _decodeFirstFrameImage(
      manager: manager,
      url: url,
      targetSize: targetSize,
    );
    await _cacheThumbnail(manager, key, image);
    _knownThumbnailKeys.add(key);
  } on _ThumbnailCancelled {
    // 面板关闭时主动取消，静默丢弃即可。
  } finally {
    image?.dispose();
  }
}

Future<ui.Image> _decodeFirstFrameImage({
  required BaseCacheManager manager,
  required String url,
  required int targetSize,
}) async {
  final generation = _thumbnailGeneration;
  void checkCancel() {
    if (_thumbnailGeneration != generation) throw const _ThumbnailCancelled();
  }

  final file = await manager.getSingleFile(url);
  checkCancel();
  final bytes = await file.readAsBytes();
  checkCancel();

  final isAvif = _bytesLookLikeAvif(bytes);
  final semaphore = isAvif ? _avifSemaphore : _nonAvifSemaphore;
  await semaphore.acquire();
  try {
    checkCancel();
    final src = await _decodeFirstFrame(url, bytes);
    checkCancel();
    if (src.width > targetSize || src.height > targetSize) {
      final resized = await _resize(src, targetSize);
      src.dispose();
      return resized;
    }
    return src;
  } finally {
    semaphore.release();
  }
}

Future<ui.Image> _decodeFirstFrame(String url, Uint8List bytes) async {
  if (_bytesLookLikeAvif(bytes)) {
    final frames = await fa.decodeAvif(bytes);
    if (frames.isEmpty) throw StateError('AVIF has no frames: $url');
    final first = frames.first.image;
    for (var i = 1; i < frames.length; i++) {
      frames[i].image.dispose();
    }
    return first;
  }

  final reply = await _DecoderWorkerPool.instance.decode(bytes);
  if (reply == null) throw StateError('decode cancelled: $url');
  if (reply.unsupported) return _decodeFirstFrameViaFlutterCodec(bytes);
  if (reply.rgba == null) {
    throw StateError('decode failed: $url (${reply.error})');
  }
  return _rgbaToUiImage(reply.rgba!, reply.width, reply.height);
}

Future<void> _writeThumbnailFromReply({
  required String url,
  required Uint8List bytes,
  required _DecodeReply reply,
  required int targetSize,
  required BaseCacheManager cacheManager,
}) async {
  ui.Image? src;
  ui.Image? display;
  try {
    if (reply.rgba != null) {
      src = await _rgbaToUiImage(reply.rgba!, reply.width, reply.height);
    } else if (reply.unsupported) {
      src = await _decodeFirstFrameViaFlutterCodec(bytes);
    } else {
      return;
    }
    display = (src.width > targetSize || src.height > targetSize)
        ? await _resize(src, targetSize)
        : src;
    final key = _thumbnailCacheKey(url, targetSize);
    await _cacheThumbnail(cacheManager, key, display);
    _knownThumbnailKeys.add(key);
  } catch (e) {
    debugPrint('[StickerThumbnail] write failed $url: $e');
  } finally {
    if (display != null && display != src) display.dispose();
    src?.dispose();
  }
}

Future<ui.Image> _decodeFirstFrameViaFlutterCodec(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final codec = await ui.instantiateImageCodecFromBuffer(buffer);
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}

Future<ui.Image> _rgbaToUiImage(Uint8List rgba, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

Future<void> _cacheThumbnail(
  BaseCacheManager manager,
  String key,
  ui.Image image,
) async {
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return;
    await manager.putFile(key, data.buffer.asUint8List(), fileExtension: 'png');
  } catch (_) {
    // 缩略图缓存失败不影响当前显示。
  }
}

Future<ui.Image> _resize(ui.Image src, int maxDim) async {
  final ratio = src.width / src.height;
  final int width;
  final int height;
  if (ratio >= 1) {
    width = maxDim;
    height = (maxDim / ratio).round().clamp(1, maxDim);
  } else {
    height = maxDim;
    width = (maxDim * ratio).round().clamp(1, maxDim);
  }
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    src,
    ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.low,
  );
  final picture = recorder.endRecording();
  final result = await picture.toImage(width, height);
  picture.dispose();
  return result;
}

class _Semaphore {
  _Semaphore(this.maxCount);

  final int maxCount;
  int _current = 0;
  final _queue = <Completer<void>>[];

  Future<void> acquire() {
    if (_current < maxCount) {
      _current++;
      return SynchronousFuture(null);
    }
    final completer = Completer<void>();
    _queue.add(completer);
    return completer.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _current--;
    }
  }
}

class _DecodeReply {
  const _DecodeReply.ok(this.width, this.height, this.rgba)
    : error = null,
      unsupported = false;

  const _DecodeReply.unsupported()
    : width = 0,
      height = 0,
      rgba = null,
      error = null,
      unsupported = true;

  const _DecodeReply.err(this.error)
    : width = 0,
      height = 0,
      rgba = null,
      unsupported = false;

  final int width;
  final int height;
  final Uint8List? rgba;
  final Object? error;
  final bool unsupported;
}

class _DecoderWorkerPool {
  _DecoderWorkerPool._();
  static final _DecoderWorkerPool instance = _DecoderWorkerPool._();

  SendPort? _sendPort;
  Future<void>? _initFuture;
  int _nextTaskId = 0;
  final Map<int, Completer<_DecodeReply>> _pending = {};

  Future<void> _ensureInit() {
    if (_sendPort != null) return Future.value();
    if (_initFuture != null) return _initFuture!;

    final ready = Completer<void>();
    _initFuture = ready.future;
    final receivePort = ReceivePort();
    receivePort.listen((dynamic msg) {
      if (msg is SendPort) {
        _sendPort = msg;
        if (!ready.isCompleted) ready.complete();
        return;
      }
      if (msg is List && msg.length == 2 && msg[0] is int) {
        final taskId = msg[0] as int;
        final reply = msg[1] as _DecodeReply;
        _pending.remove(taskId)?.complete(reply);
      }
    });
    Isolate.spawn<SendPort>(
      _decoderWorkerEntry,
      receivePort.sendPort,
      debugName: 'StickerThumbnailWorker',
    );
    return _initFuture!;
  }

  Future<_DecodeReply?> decode(Uint8List bytes) async {
    await _ensureInit();
    final taskId = _nextTaskId++;
    final completer = Completer<_DecodeReply>();
    _pending[taskId] = completer;
    _sendPort!.send([taskId, bytes]);
    return completer.future;
  }
}

@pragma('vm:entry-point')
void _decoderWorkerEntry(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);
  receivePort.listen((dynamic msg) {
    if (msg is! List || msg.length != 2) return;
    final taskId = msg[0] as int;
    final bytes = msg[1] as Uint8List;
    try {
      final decoded = NativeAnimatedImageFfi.instance.decode(bytes);
      if (decoded.frames.isEmpty) {
        mainSendPort.send([taskId, const _DecodeReply.err('empty')]);
        return;
      }
      final first = decoded.frames.first;
      mainSendPort.send([
        taskId,
        _DecodeReply.ok(decoded.width, decoded.height, first.rgba),
      ]);
    } on NativeAnimatedImageException catch (e) {
      if (e.code == _kErrUnsupported) {
        mainSendPort.send([taskId, const _DecodeReply.unsupported()]);
      } else {
        mainSendPort.send([taskId, _DecodeReply.err(e)]);
      }
    } catch (e) {
      mainSendPort.send([taskId, _DecodeReply.err(e)]);
    }
  });
}
