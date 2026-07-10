import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/image_decode_constraints.dart';

void main() {
  test('decode cap 使用 fit 策略同时限制宽高', () {
    final provider = resizeImageToFit(
      MemoryImage(Uint8List(1)),
      maxWidth: 1080,
      maxHeight: 4096,
    );

    expect(provider.width, 1080);
    expect(provider.height, 4096);
    expect(provider.policy, ResizeImagePolicy.fit);
  });

  test('decode cap 会把非法尺寸收敛为最小正值', () {
    final provider = resizeImageToFit(
      MemoryImage(Uint8List(1)),
      maxWidth: 0,
      maxHeight: -10,
    );

    expect(provider.width, 1);
    expect(provider.height, 1);
  });
}
