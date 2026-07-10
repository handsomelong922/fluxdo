import 'dart:collection';

import 'package:flutter/material.dart';

import '../../../utils/image_decode_constraints.dart';
import '../../common/hero_image.dart';

/// 帖子正文图片：由 sliver 虚拟化控制挂载，并在解码阶段限制纹理尺寸。
class LazyImage extends StatefulWidget {
  /// 长截图等窄高图的解码高度上限（物理像素）。
  static const int maxDecodeHeight = 4096;
  static const int _maxKnownAspectRatios = 512;
  static final LinkedHashMap<String, double> _knownAspectRatios =
      LinkedHashMap<String, double>();

  @visibleForTesting
  static void debugRememberAspectRatio(String key, double ratio) {
    _rememberAspectRatio(key, ratio);
  }

  @visibleForTesting
  static void debugClearKnownAspectRatios() {
    _knownAspectRatios.clear();
  }

  static void _rememberAspectRatio(String key, double ratio) {
    if (key.isEmpty || ratio <= 0) return;
    _knownAspectRatios.remove(key);
    _knownAspectRatios[key] = ratio;
    while (_knownAspectRatios.length > _maxKnownAspectRatios) {
      _knownAspectRatios.remove(_knownAspectRatios.keys.first);
    }
  }

  final ImageProvider imageProvider;
  final double? width;
  final double? height;
  final BoxFit fit;
  final String heroTag;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final GestureTapUpCallback? onSecondaryTapUp;
  final String? cacheKey;

  /// 保留旧构造参数兼容调用方；当前加载时机由 sliver 和 Flutter
  /// ScrollAwareImageProvider 决定，不再创建逐图 VisibilityDetector。
  final double visibilityThreshold;

  const LazyImage({
    super.key,
    required this.imageProvider,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    required this.heroTag,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapUp,
    this.cacheKey,
    this.visibilityThreshold = 0.01,
  });

  @override
  State<LazyImage> createState() => _LazyImageState();
}

class _LazyImageState extends State<LazyImage> {
  double? _resolvedRatio;
  ImageStream? _ratioStream;
  ImageStreamListener? _ratioListener;

  late final DisposableBuildContext<State<LazyImage>> _scrollAwareContext =
      DisposableBuildContext<State<LazyImage>>(this);

  bool get _hasFixedBox =>
      widget.width != null && widget.height != null && widget.height! > 0;

  String get _ratioCacheKey => widget.cacheKey ?? widget.heroTag;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveRatioIfNeeded();
  }

  @override
  void didUpdateWidget(covariant LazyImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider ||
        oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height) {
      _stopRatioResolve();
      _resolvedRatio = null;
      _resolveRatioIfNeeded();
    }
  }

  @override
  void dispose() {
    _stopRatioResolve();
    _scrollAwareContext.dispose();
    super.dispose();
  }

  int _targetDecodeWidth(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final logicalWidth = widget.width ?? MediaQuery.sizeOf(context).width;
    return (logicalWidth * dpr).round().clamp(1, 1 << 16);
  }

  ImageProvider _buildProvider(BuildContext context) {
    return resizeImageToFit(
      widget.imageProvider,
      maxWidth: _targetDecodeWidth(context),
      maxHeight: LazyImage.maxDecodeHeight,
    );
  }

  void _resolveRatioIfNeeded() {
    if (_hasFixedBox || _ratioListener != null) return;

    final knownRatio = LazyImage._knownAspectRatios[_ratioCacheKey];
    if (knownRatio != null) {
      LazyImage._rememberAspectRatio(_ratioCacheKey, knownRatio);
      _resolvedRatio = knownRatio;
      return;
    }

    final provider = _buildProvider(context);
    final stream = ScrollAwareImageProvider(
      context: _scrollAwareContext,
      imageProvider: provider,
    ).resolve(createLocalImageConfiguration(context));

    void onImage(ImageInfo info, bool synchronousCall) {
      final ratio = info.image.height == 0
          ? null
          : info.image.width / info.image.height;
      info.dispose();
      if (ratio == null || ratio <= 0) return;

      _rememberRatio(ratio);
      _stopRatioResolve();
      if (synchronousCall) {
        _resolvedRatio = ratio;
      } else if (mounted &&
          (_resolvedRatio == null || (ratio - _resolvedRatio!).abs() >= 0.01)) {
        setState(() => _resolvedRatio = ratio);
      }
    }

    final listener = ImageStreamListener(onImage, onError: (_, _) {});
    _ratioStream = stream;
    _ratioListener = listener;
    stream.addListener(listener);
  }

  void _rememberRatio(double ratio) {
    LazyImage._rememberAspectRatio(_ratioCacheKey, ratio);
  }

  void _stopRatioResolve() {
    final listener = _ratioListener;
    if (listener != null) {
      _ratioStream?.removeListener(listener);
    }
    _ratioListener = null;
    _ratioStream = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget buildLoadingShell() {
      return Container(
        width: widget.width,
        height: widget.height ?? 200,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
      );
    }

    final imageChild = Image(
      image: _buildProvider(context),
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return buildLoadingShell();
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: widget.width,
          height: widget.height ?? 200,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.2,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.broken_image,
            color: theme.colorScheme.outline,
            size: 32,
          ),
        );
      },
    );

    Widget imageWidget = RepaintBoundary(
      child: HeroImage(
        heroTag: widget.heroTag,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onSecondaryTapUp: widget.onSecondaryTapUp,
        child: imageChild,
      ),
    );

    if (_hasFixedBox) {
      return AspectRatio(
        aspectRatio: widget.width! / widget.height!,
        child: imageWidget,
      );
    }

    final knownRatio =
        _resolvedRatio ?? LazyImage._knownAspectRatios[_ratioCacheKey];
    if (knownRatio != null && knownRatio > 0) {
      imageWidget = AspectRatio(aspectRatio: knownRatio, child: imageWidget);
    }
    return imageWidget;
  }
}
