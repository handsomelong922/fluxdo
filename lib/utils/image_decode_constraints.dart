import 'package:flutter/painting.dart';

/// 根据真实可见宽度计算正文图片解码宽度（物理像素）。
///
/// Discourse HTML 的 width 属性可能大于移动端视口；若直接乘 DPR，会把实际只
/// 显示为屏幕宽的图片按桌面声明尺寸解码，显著放大纹理与 ImageCache 压力。
int targetImageDecodeWidth({
  required double? declaredLogicalWidth,
  required double viewportLogicalWidth,
  required double devicePixelRatio,
}) {
  final safeViewport = viewportLogicalWidth.clamp(1.0, 1 << 16).toDouble();
  final declared = declaredLogicalWidth;
  final logicalWidth = declared != null && declared > 0
      ? declared.clamp(1.0, safeViewport).toDouble()
      : safeViewport;
  return (logicalWidth * devicePixelRatio).round().clamp(1, 1 << 16);
}

/// 用解码阶段的 fit 约束限制图片物理像素尺寸，保持原始宽高比。
ResizeImage resizeImageToFit(
  ImageProvider provider, {
  required int maxWidth,
  required int maxHeight,
}) {
  return ResizeImage(
    provider,
    width: maxWidth.clamp(1, 1 << 16),
    height: maxHeight.clamp(1, 1 << 16),
    policy: ResizeImagePolicy.fit,
  );
}
