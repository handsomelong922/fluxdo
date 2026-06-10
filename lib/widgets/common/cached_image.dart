import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:native_animated_image/native_animated_image.dart'
    show NativeAnimatedImageProvider;

import '../../services/discourse_cache_manager.dart';
import '../../services/sticker_thumbnail_provider.dart';

/// 统一的缓存网络图片组件
///
/// 自动处理 AVIF、动图和普通格式。直接使用 Flutter [Image] + [frameBuilder]，
/// 不依赖 OctoImage，避免每张图加载时创建多层动画包装。
///
/// [thumbnailMode] 只用于 sticker/emoji grid：动图首帧会被缩放并缓存成 PNG，
/// 普通帖子图片不要开启，否则动画会变成静态首帧。
class CachedImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final BaseCacheManager? cacheManager;

  /// 限制图片在内存中的解码尺寸。
  ///
  /// 对非 AVIF 图片（含 GIF）：通过 [ResizeImage] 让 codec 按目标尺寸解码。
  /// 对 AVIF 图片：触发 PNG 缩略图缓存路径，首帧解码后缩放存为 PNG，
  /// 后续直接走 Flutter 内置 PNG codec（毫秒级），完全跳过 AV1 解码。
  final int? memCacheWidth;
  final int? memCacheHeight;

  /// 仅取第一帧并走 PNG 缩略图缓存。
  final bool thumbnailMode;

  /// 图片加载中显示的占位组件
  final WidgetBuilder? placeholder;

  /// 图片加载失败时显示的组件
  final ImageErrorWidgetBuilder? errorBuilder;

  /// 图片淡入时长（保留 API 兼容，暂不使用）
  final Duration fadeInDuration;

  /// 占位组件淡出时长（保留 API 兼容，暂不使用）
  final Duration fadeOutDuration;

  const CachedImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit,
    this.cacheManager,
    this.memCacheWidth,
    this.memCacheHeight,
    this.thumbnailMode = false,
    this.placeholder,
    this.errorBuilder,
    this.fadeInDuration = const Duration(milliseconds: 300),
    this.fadeOutDuration = const Duration(milliseconds: 300),
  });

  @override
  Widget build(BuildContext context) {
    final hasTargetSize = memCacheWidth != null || memCacheHeight != null;
    final targetSize = hasTargetSize
        ? (memCacheWidth ?? memCacheHeight)!
        : null;

    final provider = _resolveProvider(hasTargetSize, targetSize);

    return Image(
      image: provider,
      width: width,
      height: height,
      fit: fit,
      gaplessPlayback: true,
      frameBuilder: placeholder != null ? _buildFrame : null,
      errorBuilder: errorBuilder ?? _defaultErrorBuilder,
    );
  }

  ImageProvider _resolveProvider(bool hasTargetSize, int? targetSize) {
    if (thumbnailMode &&
        hasTargetSize &&
        StickerThumbnailProvider.supports(url)) {
      return StickerThumbnailProvider(
        url,
        targetSize: targetSize!,
        cacheManager: cacheManager,
      );
    }

    final lower = url.toLowerCase();
    if (lower.endsWith('.avif')) {
      return AvifImageProvider(url, cacheManager: cacheManager);
    }

    if (lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.apng')) {
      final cache = cacheManager ?? DiscourseCacheManager();
      return NativeAnimatedImageProvider.fromBytesProvider(
        loader: () async {
          final file = await cache.getSingleFile(url);
          final bytes = await file.readAsBytes();
          if (bytes.isEmpty) {
            throw Exception('empty image bytes: $url');
          }
          return bytes;
        },
        tag: url,
      );
    }

    ImageProvider provider = CachedNetworkImageProvider(
      url,
      cacheManager: cacheManager,
    );
    if (hasTargetSize) {
      provider = ResizeImage(
        provider,
        width: memCacheWidth,
        height: memCacheHeight,
      );
    }
    return provider;
  }

  Widget _buildFrame(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    // 图片已加载或同步加载：直接显示
    if (wasSynchronouslyLoaded || frame != null) return child;
    // 图片未加载：显示占位
    return placeholder!(context);
  }

  static Widget _defaultErrorBuilder(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    return const SizedBox.shrink();
  }
}
