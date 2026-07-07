import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/common/hero_image.dart';
import 'package:fluxdo/widgets/content/discourse_html_content/lazy_image.dart';
import 'package:fluxdo/widgets/content/lazy_load_scope.dart';
import 'package:visibility_detector/visibility_detector.dart';

final Uint8List _onePixelPng = Uint8List.fromList(const <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0x00,
  0x00,
  0x03,
  0x01,
  0x01,
  0x00,
  0x18,
  0xDD,
  0x8D,
  0xB1,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

void main() {
  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  testWidgets('LazyImage defers visible loads while pause scope is active', (
    tester,
  ) async {
    final paused = ValueNotifier<bool>(true);
    addTearDown(paused.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 120,
              child: LazyLoadScope(
                child: LazyLoadPauseScope(
                  notifier: paused,
                  child: LazyImage(
                    imageProvider: MemoryImage(_onePixelPng),
                    width: 120,
                    height: 120,
                    heroTag: 'lazy-image-test',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    VisibilityDetectorController.instance.notifyNow();
    await tester.pump();

    expect(find.byType(HeroImage), findsNothing);

    paused.value = false;
    await tester.pump();
    await tester.pump();

    expect(find.byType(HeroImage), findsOneWidget);
  });
}
