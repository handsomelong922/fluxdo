import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/topic_linear_loading_indicator.dart';

void main() {
  test('mobile loading bar animation uses faster cycle', () {
    expect(
      topicLoadingBarAnimationDuration,
      const Duration(milliseconds: 1050),
    );
  });

  testWidgets(
    'renders desktop linear progress indicator without circular spinner',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: TopicLinearLoadingIndicator())),
      );

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('renders animated mobile loading bar that keeps moving', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TopicLinearLoadingIndicator())),
    );

    expect(find.byType(LinearProgressIndicator), findsNothing);

    final movingBarFinder = find.descendant(
      of: find.byType(TopicLinearLoadingIndicator),
      matching: find.byType(Positioned),
    );
    expect(movingBarFinder, findsOneWidget);

    final first = tester.widget<Positioned>(movingBarFinder).left;
    await tester.pump(const Duration(milliseconds: 600));
    final second = tester.widget<Positioned>(movingBarFinder).left;

    expect(second, isNot(first));
  });
}
