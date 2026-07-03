import 'package:flutter/material.dart';

/// 全息渐变动画文字（模拟 CSS holographic 效果）
class HolographicText extends StatelessWidget {
  final String text;
  final double fontSize;

  const HolographicText({
    super.key,
    required this.text,
    required this.fontSize,
  });

  // 深色背景：高饱和亮色
  static const _darkColors = [
    Color(0xFFFF00FF), // magenta
    Color(0xFF00FFFF), // cyan
    Color(0xFFFFFF00), // yellow
    Color(0xFFFF00FF), // magenta
    Color(0xFF00FFFF), // cyan
  ];

  // 浅色背景：降低明度，保证可读性
  static const _lightColors = [
    Color(0xFFCC00CC), // dark magenta
    Color(0xFF0099AA), // dark cyan
    Color(0xFFCC8800), // dark gold
    Color(0xFFCC00CC), // dark magenta
    Color(0xFF0099AA), // dark cyan
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? _darkColors : _lightColors;

    // 使用静态渐变，保留辨识度同时避免列表中常驻 60fps 动画。
    return RepaintBoundary(
      child: ShaderMask(
        shaderCallback: (bounds) {
          return LinearGradient(
            colors: colors,
            stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            tileMode: TileMode.clamp,
          ).createShader(bounds);
        },
        blendMode: BlendMode.srcIn,
        child: Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }
}
