import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/navigation/page_transition_preferences.dart';

void main() {
  group('AppPageTransition', () {
    test('parses stored keys with platform fallback', () {
      expect(AppPageTransition.fromStorageKey('fade'), AppPageTransition.fade);
      expect(
        AppPageTransition.fromStorageKey('unknown'),
        AppPageTransition.platform,
      );
      expect(
        AppPageTransition.fromStorageKey(null),
        AppPageTransition.platform,
      );
    });
  });

  group('effectiveAppPageTransition', () {
    test(
      'uses no-snapshot platform transition when loading animations reduce',
      () {
        expect(
          effectiveAppPageTransition(
            transition: AppPageTransition.platform,
            reduceLoadingAnimations: true,
          ),
          AppPageTransition.noSnapshot,
        );
        expect(
          effectiveAppPageTransition(
            transition: AppPageTransition.fade,
            reduceLoadingAnimations: true,
          ),
          AppPageTransition.fade,
        );
      },
    );
  });

  group('buildAppPageTransitionsTheme', () {
    test(
      'keeps Cupertino transition on Apple platforms in no-snapshot mode',
      () {
        final theme = buildAppPageTransitionsTheme(
          transition: AppPageTransition.platform,
          reduceLoadingAnimations: true,
        );

        expect(
          theme.builders[TargetPlatform.iOS],
          isA<CupertinoPageTransitionsBuilder>(),
        );
        expect(
          theme.builders[TargetPlatform.macOS],
          isA<CupertinoPageTransitionsBuilder>(),
        );
        expect(theme.builders[TargetPlatform.android], isNotNull);
      },
    );

    test(
      'applies custom builders to every platform for explicit transitions',
      () {
        final theme = buildAppPageTransitionsTheme(
          transition: AppPageTransition.fade,
          reduceLoadingAnimations: false,
        );

        for (final platform in TargetPlatform.values) {
          expect(theme.builders[platform], isNotNull);
        }
      },
    );
  });

  group('PopGesturePassthrough', () {
    testWidgets('does not hit test while route animation reverses', (
      tester,
    ) async {
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 100),
        value: 1,
      );
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: PopGesturePassthrough(
            animation: controller,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => tapped = true,
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      );

      controller.reverse();
      await tester.pump();
      await tester.tap(find.byType(GestureDetector), warnIfMissed: false);

      expect(tapped, isFalse);

      controller.dispose();
    });
  });
}
