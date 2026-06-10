import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';

class FloatingLogo extends StatefulWidget {
  const FloatingLogo({super.key, this.size = 120, this.glowSize = 100});

  final double size;
  final double glowSize;

  @override
  State<FloatingLogo> createState() => _FloatingLogoState();
}

class _FloatingLogoState extends State<FloatingLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: -10, end: 10).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _animation.value),
          child: child,
        );
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: widget.glowSize,
            height: widget.glowSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(
                    alpha: isDark ? 0.3 : 0.2,
                  ),
                  blurRadius: 60,
                  spreadRadius: 20,
                ),
              ],
            ),
          ),
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: ScalableImageWidget.fromSISource(
              si: ScalableImageSource.fromSvg(
                DefaultAssetBundle.of(context),
                'assets/logo.svg',
                warnF: (_) {},
              ),
            ),
          ),
        ],
      ),
    );
  }
}
