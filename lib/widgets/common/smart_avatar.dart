import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:jovial_svg/jovial_svg.dart';
import '../../models/avatar_url_policy.dart';
import '../../services/discourse_cache_manager.dart';
import '../../utils/svg_utils.dart';

/// 智能头像组件
///
/// 使用 CachedNetworkImage 加载图片，自动支持 GIF 动画。
/// 普通静态头像直接走位图加载；仅在解码失败时再回退检测 SVG，
/// 避免长列表里每个头像都额外触发一次缓存探测。
class SmartAvatar extends StatefulWidget {
  final String? imageUrl;
  final double radius;
  final String? fallbackText;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final BoxBorder? border;

  const SmartAvatar({
    super.key,
    this.imageUrl,
    required this.radius,
    this.fallbackText,
    this.backgroundColor,
    this.foregroundColor,
    this.border,
  });

  @override
  State<SmartAvatar> createState() => _SmartAvatarState();
}

class _SmartAvatarState extends State<SmartAvatar> {
  static final DiscourseCacheManager _cacheManager = DiscourseCacheManager();

  String? _svgContent;
  bool _isSvgDetected = false;
  String? _lastResolvedImageUrl;

  @override
  void didUpdateWidget(SmartAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      // URL 变化时重置 SVG 状态
      _svgContent = null;
      _isSvgDetected = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AvatarUrlPolicy.revisionListenable,
      builder: (context, _, _) => _buildAvatar(context),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final theme = Theme.of(context);
    // 默认透明背景，只有在需要 fallback 时才用主题色
    final bgColor = widget.backgroundColor ?? Colors.transparent;
    final fgColor =
        widget.foregroundColor ?? theme.colorScheme.onPrimaryContainer;

    // 计算边框宽度，边框包含在 radius 内部
    double borderWidth = 0;
    if (widget.border is Border) {
      borderWidth = (widget.border as Border).top.width;
    }
    final innerRadius = widget.radius - borderWidth;
    final innerSize = innerRadius * 2;
    final imageUrl = AvatarUrlPolicy.resolveDirectAvatarUrl(
      widget.imageUrl,
      size: innerSize.round(),
    );
    if (_lastResolvedImageUrl != imageUrl) {
      _lastResolvedImageUrl = imageUrl;
      _svgContent = null;
      _isSvgDetected = false;
    }

    Widget child;
    if (imageUrl.isEmpty) {
      child = _buildFallback(fgColor, innerRadius);
    } else if (_isSvgDetected && _svgContent != null) {
      // 已检测到 SVG，直接渲染
      child =
          _buildSvg(_svgContent!, innerSize) ??
          _buildFallback(fgColor, innerRadius);
    } else if (AvifImageProvider.isAvifUrl(imageUrl) ||
        isNativeAnimatedUrl(imageUrl)) {
      child = RepaintBoundary(
        child: Image(
          image: discourseImageProvider(imageUrl),
          width: innerSize,
          height: innerSize,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          frameBuilder: (context, displayChild, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return displayChild;
            return _buildLoading(fgColor, innerRadius);
          },
          errorBuilder: (context, error, stack) =>
              _buildFallback(fgColor, innerRadius),
        ),
      );
    } else {
      final shouldTrySvgFallback = SvgUtils.looksLikeSvgUrl(imageUrl);
      child = CachedNetworkImage(
        imageUrl: imageUrl,
        cacheManager: _cacheManager,
        width: innerSize,
        height: innerSize,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (context, url) => _buildLoading(fgColor, innerRadius),
        errorWidget: (context, url, error) => shouldTrySvgFallback
            ? _SvgFallbackBuilder(
                imageUrl: imageUrl,
                cacheManager: _cacheManager,
                size: innerSize,
                onSvgDetected: (detectedSvgContent) {
                  // 缓存 SVG 内容，下次直接渲染。
                  if (mounted) {
                    setState(() {
                      _svgContent = detectedSvgContent;
                      _isSvgDetected = true;
                    });
                  }
                },
                fallback: _buildFallback(fgColor, innerRadius),
              )
            : _buildFallback(fgColor, innerRadius),
      );
    }

    // 使用 BoxDecoration + shape: circle 确保 Hero 动画时保持圆形
    // ClipOval 在 Hero 飞行时不会被正确应用
    Widget avatar = Container(
      width: innerRadius * 2,
      height: innerRadius * 2,
      decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    // 如果有边框，在外层添加，总尺寸保持 radius * 2
    if (widget.border != null) {
      avatar = Container(
        width: widget.radius * 2,
        height: widget.radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: widget.border,
        ),
        alignment: Alignment.center,
        child: avatar,
      );
    }

    return avatar;
  }

  Widget? _buildSvg(String svgContent, double size) {
    try {
      final si = ScalableImage.fromSvgString(svgContent, warnF: (_) {});
      return SizedBox(
        width: size,
        height: size,
        child: ScalableImageWidget(si: si, fit: BoxFit.cover),
      );
    } catch (_) {
      return null;
    }
  }

  Widget _buildLoading(Color fgColor, double radius) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fgColor.withValues(alpha: 0.08),
      ),
    );
  }

  Widget _buildFallback(Color fgColor, double radius) {
    if (widget.fallbackText != null && widget.fallbackText!.isNotEmpty) {
      return Center(
        child: Text(
          widget.fallbackText![0].toUpperCase(),
          style: TextStyle(
            color: fgColor,
            fontWeight: FontWeight.w600,
            fontSize: radius * 0.8,
          ),
        ),
      );
    }
    return Center(
      child: Icon(Icons.person, size: radius, color: fgColor),
    );
  }
}

/// SVG 检测和渲染组件
///
/// 当 CachedNetworkImage 解码失败时，检测缓存文件是否为 SVG
class _SvgFallbackBuilder extends StatefulWidget {
  final String imageUrl;
  final DiscourseCacheManager cacheManager;
  final double size;
  final void Function(String svgContent) onSvgDetected;
  final Widget fallback;

  const _SvgFallbackBuilder({
    required this.imageUrl,
    required this.cacheManager,
    required this.size,
    required this.onSvgDetected,
    required this.fallback,
  });

  @override
  State<_SvgFallbackBuilder> createState() => _SvgFallbackBuilderState();
}

class _SvgFallbackBuilderState extends State<_SvgFallbackBuilder> {
  String? _svgContent;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _checkForSvg();
  }

  Future<void> _checkForSvg() async {
    try {
      final file = await widget.cacheManager.getSingleFile(widget.imageUrl);
      final bytes = await file.readAsBytes();

      if (bytes.isEmpty || !mounted) return;

      if (SvgUtils.isSvgBytes(bytes)) {
        final svgString = SvgUtils.sanitize(SvgUtils.decodeSvgBytes(bytes));
        if (mounted) {
          setState(() {
            _svgContent = svgString;
            _checked = true;
          });
          widget.onSvgDetected(svgString);
        }
      } else {
        if (mounted) {
          setState(() => _checked = true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checked = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_svgContent != null) {
      try {
        final si = ScalableImage.fromSvgString(_svgContent!, warnF: (_) {});
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: ScalableImageWidget(si: si, fit: BoxFit.cover),
        );
      } catch (_) {
        return widget.fallback;
      }
    }

    if (!_checked) {
      // 检测中，显示空白避免闪烁
      return const SizedBox.shrink();
    }

    return widget.fallback;
  }
}
