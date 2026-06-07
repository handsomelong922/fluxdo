import 'package:flutter/material.dart';

/// 头像脉冲光晕效果
class AvatarGlow extends StatefulWidget {
  final Widget child;
  final Color glowColor;
  final bool animate;

  const AvatarGlow({
    super.key,
    required this.child,
    this.glowColor = const Color(0xFFF5BF03),
    this.animate = true,
  });

  @override
  State<AvatarGlow> createState() => _AvatarGlowState();
}

class _AvatarGlowState extends State<AvatarGlow>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _startAnimation();
    }
  }

  @override
  void didUpdateWidget(AvatarGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate == widget.animate) return;
    if (widget.animate) {
      _startAnimation();
    } else {
      _controller?.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return _buildGlow(child: widget.child, t: 0.35);
    }

    final controller = _controller ?? _startAnimation();
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // ease-in-out 曲线
        final t = Curves.easeInOut.transform(controller.value);
        return _buildGlow(child: child!, t: t);
      },
      child: widget.child,
    );
  }

  AnimationController _startAnimation() {
    final controller =
        _controller ??
        AnimationController(vsync: this, duration: const Duration(seconds: 5));
    _controller = controller;
    if (!controller.isAnimating) {
      controller.repeat(reverse: true);
    }
    return controller;
  }

  Widget _buildGlow({required Widget child, required double t}) {
    // 光晕半径在 8~20 之间脉冲
    final blurRadius = 8.0 + t * 12.0;
    // 透明度在 0.3~0.8 之间脉冲
    final opacity = 0.3 + t * 0.5;

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: widget.glowColor.withValues(alpha: opacity),
            blurRadius: blurRadius,
            spreadRadius: 1,
          ),
        ],
      ),
      child: child,
    );
  }
}
