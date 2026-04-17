import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../services/avif_image_provider.dart';

/// 统一的缓存网络图片组件
///
/// 自动处理 AVIF 与普通格式。直接使用 Flutter [Image] + [frameBuilder]，
/// 不依赖 OctoImage，避免每张图加载时创建 Stack + 2 FadeWidget +
/// 2 AnimationController 的开销。
///
/// 当 AVIF 图片设置了 [memCacheWidth]/[memCacheHeight] 时，自动走
/// PNG 缩略图缓存路径（只解码首帧 → 缩放 → 存 PNG），后续直接读取
/// PNG 缓存，完全跳过 AV1 解码。未设置尺寸限制时 AVIF 正常播放动画。
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
    this.placeholder,
    this.errorBuilder,
    this.fadeInDuration = const Duration(milliseconds: 300),
    this.fadeOutDuration = const Duration(milliseconds: 300),
  });

  @override
  Widget build(BuildContext context) {
    final isAvif = url.toLowerCase().endsWith('.avif');
    final hasTargetSize = memCacheWidth != null || memCacheHeight != null;

    ImageProvider provider;
    if (isAvif) {
      provider = AvifImageProvider(
        url,
        cacheManager: cacheManager,
        // 有目标尺寸 → 首帧 + PNG 缓存（静态缩略图）
        // 无目标尺寸 → 完整解码（支持动画）
        singleFrame: hasTargetSize,
        targetSize: hasTargetSize ? (memCacheWidth ?? memCacheHeight) : null,
      );
    } else {
      provider = CachedNetworkImageProvider(
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
    }

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
