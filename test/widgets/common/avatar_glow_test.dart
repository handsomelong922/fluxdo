import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/common/avatar_glow.dart';

void main() {
  testWidgets('AvatarGlow can render a static glow without ticker animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AvatarGlow(
          animate: false,
          child: SizedBox(width: 24, height: 24),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(AvatarGlow),
        matching: find.byType(AnimatedBuilder),
      ),
      findsNothing,
    );
    expect(find.byType(SizedBox), findsOneWidget);
  });
}
