import 'package:flutter/painting.dart';

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
