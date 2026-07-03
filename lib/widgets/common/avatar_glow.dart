import 'package:flutter/material.dart';

/// 头像脉冲光晕效果
class AvatarGlow extends StatefulWidget {
  final Widget child;
  final Color glowColor;

  const AvatarGlow({
    super.key,
    required this.child,
    this.glowColor = const Color(0xFFF5BF03),
  });

  @override
  State<AvatarGlow> createState() => _AvatarGlowState();
}

class _AvatarGlowState extends State<AvatarGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary 隔离 60fps 的 blurRadius/opacity 脉冲动画，
    // 避免连累整个 post item / list item 重绘。
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          // 入场时做一次增强脉冲，动画结束后停在稳定光晕，
          // 避免列表里长期维持多个 60fps 阴影动画。
          final t = Curves.easeOutCubic.transform(_controller.value);
          final blurRadius = 10.0 + t * 10.0;
          final opacity = 0.38 + t * 0.22;

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
        },
        child: widget.child,
      ),
    );
  }
}
