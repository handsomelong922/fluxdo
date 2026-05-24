import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/navigation/pop_passthrough_material_page_route.dart';

void main() {
  testWidgets('正常显示时 route 内容可以响应点击', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    var topTapCount = 0;
    var bottomTapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => bottomTapCount++,
          child: const SizedBox.expand(),
        ),
      ),
    );

    navigatorKey.currentState!.push(
      PopPassthroughMaterialPageRoute<void>(
        builder: (_) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => topTapCount++,
          child: const ColoredBox(color: Colors.white),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(find.byType(MaterialApp)));
    expect(topTapCount, 1);
    expect(bottomTapCount, 0);
  });

  testWidgets('pop reverse 动画期间 route 不拦截底层列表拖拽', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: ListView.builder(
            controller: scrollController,
            itemExtent: 64,
            itemCount: 80,
            itemBuilder: (context, index) => Text('item $index'),
          ),
        ),
      ),
    );

    navigatorKey.currentState!.push(
      PopPassthroughMaterialPageRoute<void>(
        builder: (_) => const ColoredBox(color: Colors.white),
      ),
    );
    await tester.pumpAndSettle();

    navigatorKey.currentState!.pop();
    await tester.pump();

    await tester.dragFrom(
      tester.getCenter(find.byType(MaterialApp)),
      const Offset(0, -240),
    );
    await tester.pump();

    expect(scrollController.offset, greaterThan(0));
  });
}
