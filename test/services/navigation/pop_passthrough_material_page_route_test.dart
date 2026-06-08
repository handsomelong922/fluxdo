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

  testWidgets('启用横向返回时右滑过程中露出底层 route', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final detailKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const ColoredBox(color: Colors.green, child: SizedBox.expand()),
      ),
    );

    final route = PopPassthroughMaterialPageRoute<void>(
      enableHorizontalPopGesture: true,
      builder: (_) => ColoredBox(
        key: detailKey,
        color: Colors.red,
        child: const SizedBox.expand(),
      ),
    );
    navigatorKey.currentState!.push(route);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(260, 0));
    await tester.pump();

    expect(route.animation!.value, lessThan(1.0));
    expect(route.overlayEntries.first.opaque, isFalse);
    expect(tester.getTopLeft(find.byKey(detailKey)).dx, greaterThan(0));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('启用横向返回时超过阈值释放会返回底层 route', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Text('home')),
    );

    navigatorKey.currentState!.push(
      PopPassthroughMaterialPageRoute<void>(
        enableHorizontalPopGesture: true,
        builder: (_) => const Text('detail'),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(520, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(find.text('detail'), findsNothing);
  });

  testWidgets('启用横向返回时向左拖不会误触返回', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Text('home')),
    );

    final route = PopPassthroughMaterialPageRoute<void>(
      enableHorizontalPopGesture: true,
      builder: (_) => const Text('detail'),
    );
    navigatorKey.currentState!.push(route);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(-240, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(route.animation!.value, 1.0);
    expect(find.text('detail'), findsOneWidget);
  });
}
