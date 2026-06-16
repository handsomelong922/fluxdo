import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/navigation/page_transition_preferences.dart';
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

  testWidgets('启用横向返回时仍尊重普通页面转场设置', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final detailKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData(
          pageTransitionsTheme: buildAppPageTransitionsTheme(
            transition: AppPageTransition.fade,
            reduceLoadingAnimations: false,
          ),
        ),
        home: const ColoredBox(color: Colors.green, child: SizedBox.expand()),
      ),
    );

    navigatorKey.currentState!.push(
      PopPassthroughMaterialPageRoute<void>(
        enableHorizontalPopGesture: true,
        builder: (_) => ColoredBox(
          key: detailKey,
          color: Colors.red,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(tester.getTopLeft(find.byKey(detailKey)).dx, 0);

    await tester.pumpAndSettle();
  });

  testWidgets('启用横向返回时 route 内容点击不会被手势层吞掉', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    var tapCount = 0;

    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Text('home')),
    );

    navigatorKey.currentState!.push(
      PopPassthroughMaterialPageRoute<void>(
        enableHorizontalPopGesture: true,
        builder: (_) => Scaffold(
          body: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => tapCount++,
              child: const SizedBox(
                width: 120,
                height: 120,
                child: Text('avatar-or-link'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('avatar-or-link'));
    await tester.pump();

    expect(tapCount, 1);
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

  testWidgets('启用横向返回且内容为 PageView 时右滑返回底层 route', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final pageController = PageController();
    addTearDown(pageController.dispose);

    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Text('home')),
    );

    navigatorKey.currentState!.push(
      PopPassthroughMaterialPageRoute<void>(
        enableHorizontalPopGesture: true,
        builder: (_) => PageView(
          controller: pageController,
          children: const [
            ColoredBox(color: Colors.red, child: Text('topic')),
            ColoredBox(color: Colors.blue, child: Text('ai')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(520, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(find.text('topic'), findsNothing);
  });

  testWidgets('启用横向返回时较短右滑距离也能返回底层 route', (tester) async {
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
    await gesture.moveBy(const Offset(280, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(find.text('detail'), findsNothing);
  });

  testWidgets('右滑返回手势回拉取消时不会误进入 AI 页', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final pageController = PageController();
    addTearDown(pageController.dispose);

    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Text('home')),
    );

    final route = PopPassthroughMaterialPageRoute<void>(
      enableHorizontalPopGesture: true,
      builder: (_) => PageView(
        controller: pageController,
        children: const [
          ColoredBox(color: Colors.red, child: Text('topic')),
          ColoredBox(color: Colors.blue, child: Text('ai')),
        ],
      ),
    );
    navigatorKey.currentState!.push(route);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(220, 0));
    await tester.pump();
    expect(route.animation!.value, lessThan(1.0));

    await gesture.moveBy(const Offset(-180, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('topic'), findsOneWidget);
    expect(find.text('ai'), findsNothing);
    expect(find.text('home'), findsNothing);
    expect(pageController.page, 0);
  });

  testWidgets('右滑返回手势取消后帖子按钮仍可点击', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final pageController = PageController();
    addTearDown(pageController.dispose);
    var avatarTapCount = 0;
    var favoriteTapCount = 0;

    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Text('home')),
    );

    final route = PopPassthroughMaterialPageRoute<void>(
      enableHorizontalPopGesture: true,
      builder: (_) => PageView(
        controller: pageController,
        children: [
          Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => avatarTapCount++,
                    child: const SizedBox(
                      width: 64,
                      height: 64,
                      child: Text('avatar-after-cancel'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'favorite-after-cancel',
                    onPressed: () => favoriteTapCount++,
                    icon: const Icon(Icons.bookmark_border),
                  ),
                ],
              ),
            ),
          ),
          const Scaffold(body: Center(child: Text('ai'))),
        ],
      ),
    );
    navigatorKey.currentState!.push(route);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(220, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-180, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('home'), findsNothing);
    expect(find.text('ai'), findsNothing);
    expect(route.animation!.value, 1.0);

    await tester.tap(find.text('avatar-after-cancel'));
    await tester.tap(find.byTooltip('favorite-after-cancel'));
    await tester.pump();

    expect(avatarTapCount, 1);
    expect(favoriteTapCount, 1);
  });

  testWidgets('启用横向返回且内容为 PageView 时帖子按钮仍可逐个点击', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final pageController = PageController();
    addTearDown(pageController.dispose);
    var avatarTapCount = 0;
    var linkTapCount = 0;
    var favoriteTapCount = 0;
    var shareTapCount = 0;

    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Text('home')),
    );

    navigatorKey.currentState!.push(
      PopPassthroughMaterialPageRoute<void>(
        enableHorizontalPopGesture: true,
        builder: (_) => PageView(
          controller: pageController,
          children: [
            Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => avatarTapCount++,
                      child: const SizedBox(
                        width: 64,
                        height: 64,
                        child: Text('avatar'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => linkTapCount++,
                      child: const Text('link'),
                    ),
                    IconButton(
                      tooltip: 'favorite',
                      onPressed: () => favoriteTapCount++,
                      icon: const Icon(Icons.bookmark_border),
                    ),
                    IconButton(
                      tooltip: 'share',
                      onPressed: () => shareTapCount++,
                      icon: const Icon(Icons.share),
                    ),
                  ],
                ),
              ),
            ),
            const Scaffold(body: Center(child: Text('ai'))),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('avatar'));
    await tester.tap(find.text('link'));
    await tester.tap(find.byTooltip('favorite'));
    await tester.tap(find.byTooltip('share'));
    await tester.pump();

    expect(avatarTapCount, 1);
    expect(linkTapCount, 1);
    expect(favoriteTapCount, 1);
    expect(shareTapCount, 1);
    expect(find.text('home'), findsNothing);
  });

  testWidgets('启用横向返回且内容为 PageView 时向左滑仍进入 AI 页', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final pageController = PageController();
    addTearDown(pageController.dispose);

    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Text('home')),
    );

    navigatorKey.currentState!.push(
      PopPassthroughMaterialPageRoute<void>(
        enableHorizontalPopGesture: true,
        builder: (_) => PageView(
          controller: pageController,
          children: const [
            ColoredBox(color: Colors.red, child: Text('topic')),
            ColoredBox(color: Colors.blue, child: Text('ai')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.text('topic'), const Offset(-520, 0));
    await tester.pumpAndSettle();

    expect(find.text('ai'), findsOneWidget);
    expect(find.text('home'), findsNothing);
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

  testWidgets('横向返回 blocker 激活时右滑不会触发返回动画', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final blocker = ValueNotifier<bool>(true);
    addTearDown(blocker.dispose);

    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Text('home')),
    );

    final route = PopPassthroughMaterialPageRoute<void>(
      enableHorizontalPopGesture: true,
      horizontalPopGestureBlocker: blocker,
      builder: (_) => const Text('detail'),
    );
    navigatorKey.currentState!.push(route);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(520, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(route.animation!.value, 1.0);
    expect(find.text('detail'), findsOneWidget);
    expect(find.text('home'), findsNothing);
  });
}
