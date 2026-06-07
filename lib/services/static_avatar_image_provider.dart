import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'discourse_cache_manager.dart';

ImageProvider staticAvatarImageProvider(
  String url, {
  double scale = 1.0,
  int? targetSize,
  BaseCacheManager? cacheManager,
}) {
  if (AvifImageProvider.isAvifUrl(url)) {
    return AvifImageProvider(
      url,
      scale: scale,
      cacheManager: cacheManager ?? DiscourseCacheManager(),
      singleFrame: true,
      targetSize: targetSize,
    );
  }

  return StaticAvatarImageProvider(
    url,
    scale: scale,
    cacheManager: cacheManager,
    targetSize: targetSize,
  );
}

/// 只解码头像类动态图片的第一帧，避免 GIF/WebP/APNG 在头像位置持续播放。
class StaticAvatarImageProvider
    extends ImageProvider<StaticAvatarImageProvider> {
  final String url;
  final double scale;
  final BaseCacheManager? cacheManager;
  final int? targetSize;

  const StaticAvatarImageProvider(
    this.url, {
    this.scale = 1.0,
    this.cacheManager,
    this.targetSize,
  });

  @override
  Future<StaticAvatarImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<StaticAvatarImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    StaticAvatarImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(_loadFirstFrame(key));
  }

  Future<ImageInfo> _loadFirstFrame(StaticAvatarImageProvider key) async {
    final manager = key.cacheManager ?? DiscourseCacheManager();
    final file = await manager.getSingleFile(key.url);
    final bytes = await file.readAsBytes();
    final image = await _decodeFirstFrame(bytes, key.targetSize);
    return ImageInfo(image: image, scale: key.scale);
  }

  static Future<ui.Image> _decodeFirstFrame(
    Uint8List bytes,
    int? targetSize,
  ) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetSize,
      targetHeight: targetSize,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  @override
  bool operator ==(Object other) {
    return other is StaticAvatarImageProvider &&
        other.url == url &&
        other.scale == scale &&
        other.cacheManager == cacheManager &&
        other.targetSize == targetSize;
  }

  @override
  int get hashCode => Object.hash(url, scale, cacheManager, targetSize);

  @override
  String toString() =>
      'StaticAvatarImageProvider("$url", scale: $scale, targetSize: $targetSize)';
}
