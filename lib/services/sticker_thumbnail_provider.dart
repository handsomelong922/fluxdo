import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
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

  /// 主动 cancel 所有 in-flight thumbnail decode。
  ///
  /// sticker panel dispose 时调用。Bumps 一个 generation counter,
  /// `_decodeFirstFrameImage` 内的多个 await 检查点会发现 mismatch 立即抛
  /// `_ThumbnailCancelled` 退出 —— 排队中的解码任务全部作废,panel 关闭后
  /// 不再占用解码资源。已经在跑的单张解码不可中断,但跑完即停。
  static void cancelInflight() {
    _bumpThumbnailGeneration();
  }

  final String url;
  final int targetSize;
  final double scale;
  final BaseCacheManager? cacheManager;

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
    // Phase 1: 过滤掉不支持 / 已 cache / in-flight 的 URL,异步拉 bytes。
    // AVIF 跟非 AVIF 分开:走不同的解码 backend(AVIF → flutter_avif FFI,
    // 其余 → Rust worker pool),且各自独立限流。
    //
    // 关键:用**实际 magic bytes** 而不是 URL 后缀分流。CDN 给的 .gif/.webp
    // URL 实际内容可能是 AVIF,只看后缀会让 AVIF bytes 进 Rust → crash。
    final pendingNonAvif = <(String, Uint8List)>[];
    final pendingAvifUrls = <String>[];
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
          pendingAvifUrls.add(url);
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
      await _writeThumbnailFromRustOrFallback(
        url: entry.$1,
        bytes: entry.$2,
        reply: reply,
        targetSize: targetSize,
        cacheManager: cacheManager,
      );
    }

    // Phase 2B: AVIF — 经 [precache] 逐张预热(内部 `_pendingThumbnailTasks`
    // 去重,与 grid widget 触发的现场解码互不重复;`_avifSemaphore(4)` 限流)。
    //
    // 历史:这里曾经完全跳过 AVIF prefetch —— 当时 `fa.decodeAvif` 被认为
    // 走 method channel 全帧 marshal 阻塞主 isolate。现在两个前提都变了:
    // flutter_avif 3.x 是 FFI + native port 异步(解码在 native 线程),
    // 且缩略图改为单帧解码([AvifImageProvider.decodeFirstFrame]),主
    // isolate 每张只剩一次单帧 RGBA 解包,毫秒级 → 放心预热。
    //
    // shouldContinue 在每张之间检查(切组 / 关 panel 立即停);已在跑的
    // 单张解码由 generation 检查点兜底取消(见 [cancelInflight])。
    for (final url in pendingAvifUrls) {
      if (shouldContinue != null && !shouldContinue()) return;
      try {
        await precache(url, targetSize: targetSize, cacheManager: cacheManager);
      } on _ThumbnailCancelled {
        return;
      } catch (e) {
        debugPrint('[StickerThumbnail] avif prefetch failed $url: $e');
      }
    }
  }

  static Future<void> _writeThumbnailFromRustOrFallback({
    required String url,
    required Uint8List bytes,
    required _DecodeReply reply,
    required int targetSize,
    required BaseCacheManager cacheManager,
  }) async {
    ui.Image? srcImage;
    try {
      if (reply.rgba != null) {
        srcImage = await _rgbaToUiImage(reply.rgba!, reply.width, reply.height);
      } else if (reply.unsupported) {
        // Rust 不识别 → Flutter codec(静态 webp / png / jpeg)
        try {
          srcImage = await _decodeFirstFrameViaFlutterCodec(bytes);
        } catch (e) {
          debugPrint('[StickerThumbnail] both decoders failed $url: $e');
          return;
        }
      } else {
        // decode error or cancelled
        return;
      }
      final displayImage =
          (srcImage.width > targetSize || srcImage.height > targetSize)
              ? await _resize(srcImage, targetSize)
              : srcImage;
      await _cacheThumbnail(
        cacheManager,
        _thumbnailCacheKey(url, targetSize),
        displayImage,
      );
      _knownThumbnailKeys.add(_thumbnailCacheKey(url, targetSize));
      if (displayImage != srcImage) displayImage.dispose();
    } finally {
      srcImage?.dispose();
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
    return OneFrameImageStreamCompleter(
      _loadThumbnail(key).catchError((Object e, StackTrace st) {
        // 失败的 completer 不能留在 ImageCache —— 否则同 key 的后续 Image
        // 直接复用错误结果,永久裂图直到重启(NetworkImage 官方实现同款 evict)。
        // evict 后下次 rebuild 自动重试;面板关闭触发的 _ThumbnailCancelled
        // 也走这里,重开面板即重解。
        scheduleMicrotask(() {
          PaintingBinding.instance.imageCache.evict(key);
        });
        Error.throwWithStackTrace(e, st);
      }),
    );
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

// ==================== Internal helpers ====================

/// AVIF 解码并发。
///
/// flutter_avif 3.x 是 **FFI + native port 异步**:AV1 解码跑在 native
/// 线程,主 isolate 只承担"单帧 RGBA 解包 + decodeImageFromPixels"
/// (配合 [AvifImageProvider.decodeFirstFrame] 单帧解码,每张就一次,
/// 毫秒级)。早期"method channel 全帧 marshal 阻塞主线程必须限 1 并发"
/// 的约束已不存在,放开到 4 让首开 30 张 AVIF 从串行 3-9s 变成秒级。
final _avifSemaphore = _Semaphore(4);

/// 非 AVIF (GIF / WebP / APNG) 解码并发。decode 走 `_DecoderWorkerPool`
/// (long-lived worker isolate)在后台串行,主 isolate 只做轻量 ui.Image
/// 创建,可以放开并发到 8。
///
/// 关键:跟 AVIF 用**独立** semaphore,AVIF 慢不会阻塞 GIF/WebP/APNG 解码。
final _nonAvifSemaphore = _Semaphore(8);
final _pendingThumbnailTasks = <String, Future<void>>{};
final _knownThumbnailKeys = <String>{};

/// 生成号 — 每次 [StickerThumbnailProvider.cancelInflight] 调用 ++,
/// `_decodeFirstFrameImage` 内部 await 链的多个检查点都 captures 起始号,
/// 任意 await 后比对发现 mismatch → throw 立即 abort。
///
/// 关键场景:用户打开 sticker panel,30 张缩略图同时 enqueue 排队解码。
/// 用户 0.5s 内关闭 panel,还在排队的 task 应该立即作废,不再占用解码
/// 资源(否则"关闭面板还在后台解码")。已经在跑的单张解码不可中断,
/// 但跑完即停。
int _thumbnailGeneration = 0;

/// 主动 cancel 当前所有 in-flight thumbnail decode。
/// `_decodeFirstFrameImage` 内部检查 generation,mismatch 即 throw 退出。
void _bumpThumbnailGeneration() {
  _thumbnailGeneration++;
}

class _ThumbnailCancelled implements Exception {
  const _ThumbnailCancelled();
  @override
  String toString() => 'sticker thumbnail decode cancelled';
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
  // 拿到 semaphore 槽后再检查 — 关 panel 后排队中的任务在这里立即
  // release 槽 + abort,不再发起新的解码;已经在跑的解码跑完即停。
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
    return _decodeAvifFirstFrame(bytes, url);
  }

  final reply = await _DecoderWorkerPool.instance.decode(bytes);
  if (reply == null) throw StateError('decode cancelled: $url');
  if (reply.unsupported) return _decodeFirstFrameViaFlutterCodec(bytes);
  if (reply.rgba == null) {
    throw StateError('decode failed: $url (${reply.error})');
  }
  return _rgbaToUiImage(reply.rgba!, reply.width, reply.height);
}

Future<ui.Image> _decodeAvifFirstFrame(Uint8List bytes, String url) async {
  // 增量解码:只解第 1 帧立即 dispose,不像 fa.decodeAvif 全帧解完丢 N-1 帧
  return AvifImageProvider.decodeFirstFrame(bytes);
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
