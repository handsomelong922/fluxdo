import 'package:common_ui/common_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/personal_navigation_preferences_provider.dart';
import 'package:fluxdo/widgets/common/fullscreen_swipe_back.dart';
import 'package:fluxdo/widgets/common/personal_page_transitions.dart';

var _mounts = 0;
var _pops = 0;
class _Observer extends NavigatorObserver {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _pops++;
}
class _Detail extends StatefulWidget {
  const _Detail();
  @override
  State<_Detail> createState() => _DetailState();
}
class _DetailState extends State<_Detail> {
  @override
  void initState() { super.initState(); _mounts++; }
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('detail'));
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> send(String method, [double? progress]) => binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, progress == null ? null : {
      'touchOffset': <double>[10, 300], 'progress': progress, 'swipeEdge': 0,
    })), (_) {},
  );
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }
  Future<GlobalKey<NavigatorState>> mount(WidgetTester tester, PageTransitionStyle style, {
    bool fullscreen = false, bool settle = true, bool fullscreenDialog = false,
    bool customRoute = false,
  }) async {
    _mounts = _pops = 0;
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      navigatorObservers: [_Observer()],
      theme: ThemeData(pageTransitionsTheme: personalPageTransitionsTheme(style: style, fullscreenSwipeBack: fullscreen)),
      home: const Scaffold(body: Text('home')),
    ));
    key.currentState!.push(customRoute
        ? personalPageRoute<void>(
            context: tester.element(find.text('home')),
            pageBuilder: (_, _, _) => const _Detail(),
            defaultTransitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
          )
        : MaterialPageRoute<void>(fullscreenDialog: fullscreenDialog, builder: (_) => const _Detail()));
    await tester.pump();
    if (settle) await tester.pumpAndSettle();
    return key;
  }
  Finder ancestor(Type type) => find.ancestor(of: find.text('detail'), matching: find.byType(type));
  void expectVisual(WidgetTester tester, PageTransitionStyle style, {bool gesture = false, bool settled = false}) {
    final route = ModalRoute.of(tester.element(find.text('detail')))!;
    final value = route.animation!.value;
    if (style == PageTransitionStyle.cupertino) {
      expect(tester.getTopLeft(find.text('detail')).dx, settled ? closeTo(0, .01) : greaterThan(0));
      return;
    }
    // 不是把所选动画叠到 Cupertino 平移上；只有这一层视觉驱动。
    expect(ancestor(CupertinoPageTransition), findsNothing);
    final opacity = tester.widget<FadeTransition>(ancestor(FadeTransition)).opacity.value;
    final scale = tester.widget<ScaleTransition>(ancestor(ScaleTransition)).scale.value;
    switch (style) {
      case PageTransitionStyle.fade:
        expect(scale, 1);
        expect(opacity, settled ? 1 : inExclusiveRange(0, 1));
        if (gesture) expect(opacity, closeTo(value, .000001));
        expect(tester.getTopLeft(find.text('detail')).dx, closeTo(0, .01));
      case PageTransitionStyle.scale:
        expect(opacity, 1);
        expect(scale, settled ? 1 : inExclusiveRange(.94, 1));
        if (gesture) expect(scale, closeTo(.94 + .06 * value, .000001));
      case PageTransitionStyle.none:
        expect(opacity, 1);
        expect(scale, 1);
        expect(tester.getTopLeft(find.text('detail')).dx, closeTo(0, .01));
      case PageTransitionStyle.cupertino:
        break;
    }
  }

  test('默认逐平台保留原builder；全屏手势只是装饰器', () {
    final normal = personalPageTransitionsTheme(style: PageTransitionStyle.cupertino, fullscreenSwipeBack: false);
    expect(normal.builders[TargetPlatform.android], isA<PredictiveBackCupertinoPageTransitionsBuilder>());
    expect(normal.builders[TargetPlatform.iOS], isA<CupertinoPageTransitionsBuilder>());
    final full = personalPageTransitionsTheme(style: PageTransitionStyle.cupertino, fullscreenSwipeBack: true);
    expect(full.builders[TargetPlatform.iOS], isA<FullscreenSwipeBackTransitionsBuilder>());
  });

  for (final style in PageTransitionStyle.values) {
    testWidgets('${style.name} 打开和按钮返回采用同一所选视觉', (tester) async {
      final key = await mount(tester, style, settle: false);
      await tester.pump(const Duration(milliseconds: 100));
      expectVisual(tester, style, settled: style == PageTransitionStyle.none);
      await tester.pumpAndSettle();
      expectVisual(tester, style, settled: true);
      key.currentState!.pop();
      await tester.pump();
      if (style != PageTransitionStyle.none) {
        await tester.pump(const Duration(milliseconds: 100));
        expectVisual(tester, style);
      }
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsNothing);
      expect(_mounts, 1);
      expect(_pops, 1);
      await unmount(tester);
    });

    testWidgets('${style.name} 系统预测返回所选视觉取消/提交，正文只挂载一次', (tester) async {
      final key = await mount(tester, style);
      await send('startBackGesture', 0);
      await tester.pump();
      await send('updateBackGestureProgress', .5);
      await tester.pump();
      expectVisual(tester, style, gesture: true);
      await send('cancelBackGesture');
      await tester.pumpAndSettle();
      expectVisual(tester, style, settled: true);
      expect(key.currentState!.userGestureInProgress, isFalse);
      expect(_pops, 0);
      expect(_mounts, 1);
      await send('startBackGesture', 0);
      await tester.pump();
      await send('updateBackGestureProgress', .6);
      await tester.pump();
      expectVisual(tester, style, gesture: true);
      await send('commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(find.text('detail'), findsNothing);
      expect(key.currentState!.userGestureInProgress, isFalse);
      expect(_mounts, 1);
      expect(_pops, 1);
      await unmount(tester);
    }, variant: const TargetPlatformVariant({TargetPlatform.android}));

    for (final fullscreen in [false, true]) {
      testWidgets('${style.name} ${fullscreen ? "全屏" : "边缘"}返回所选视觉取消/提交', (tester) async {
        final key = await mount(tester, style, fullscreen: fullscreen);
        final origin = Offset(fullscreen ? 200 : 5, 300);
        final cancel = await tester.startGesture(origin);
        await cancel.moveBy(const Offset(30, 0));
        await tester.pump();
        await cancel.moveBy(const Offset(110, 0));
        await tester.pump();
        expectVisual(tester, style, gesture: true);
        await tester.pump(const Duration(milliseconds: 300));
        await cancel.up();
        await tester.pumpAndSettle();
        expectVisual(tester, style, settled: true);
        expect(_mounts, 1);
        expect(_pops, 0);
        final commit = await tester.startGesture(origin);
        await commit.moveBy(const Offset(30, 0));
        await tester.pump();
        await commit.moveBy(const Offset(480, 0));
        await tester.pump();
        expectVisual(tester, style, gesture: true);
        await tester.pump(const Duration(milliseconds: 300));
        await commit.up();
        await tester.pumpAndSettle();
        expect(find.text('home'), findsOneWidget);
        expect(key.currentState!.userGestureInProgress, isFalse);
        expect(_mounts, 1);
        expect(_pops, 1);
        await unmount(tester);
      }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
    }

    if (style != PageTransitionStyle.cupertino) {
      for (final customRoute in [false, true]) {
        testWidgets('${style.name} ${customRoute ? "自定义普通路由" : "fullscreenDialog"}也使用所选视觉', (tester) async {
          final key = await mount(tester, style, settle: false, fullscreenDialog: !customRoute, customRoute: customRoute);
          await tester.pump(const Duration(milliseconds: 100));
          expectVisual(tester, style, settled: style == PageTransitionStyle.none);
          await tester.pumpAndSettle();
          key.currentState!.pop();
          await tester.pumpAndSettle();
          expect(_mounts, 1);
          expect(_pops, 1);
          await unmount(tester);
        });
      }
    }
  }

  for (final style in [PageTransitionStyle.fade, PageTransitionStyle.scale, PageTransitionStyle.none]) {
    testWidgets('${style.name} 全屏手势让位横向列表，边缘兜底只返回一次', (tester) async {
      _pops = 0;
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: key,
        navigatorObservers: [_Observer()],
        theme: ThemeData(pageTransitionsTheme: personalPageTransitionsTheme(style: style, fullscreenSwipeBack: true)),
        home: const Scaffold(body: Text('home')),
      ));
      key.currentState!.push(MaterialPageRoute<void>(builder: (_) => Scaffold(
        body: PageView(children: const [Center(child: Text('horizontal')), Center(child: Text('second'))]),
      )));
      await tester.pumpAndSettle();
      final scroll = await tester.startGesture(const Offset(400, 300));
      await scroll.moveBy(const Offset(-30, 0));
      await tester.pump();
      await scroll.moveBy(const Offset(-160, 0));
      await tester.pump();
      expect(key.currentState!.userGestureInProgress, isFalse);
      expect(_pops, 0);
      await scroll.up();
      await tester.pumpAndSettle();
      final back = await tester.startGesture(const Offset(5, 300));
      await back.moveBy(const Offset(30, 0));
      await tester.pump();
      await back.moveBy(const Offset(480, 0));
      await tester.pump();
      expect(key.currentState!.userGestureInProgress, isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      await back.up();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(_pops, 1);
      expect(key.currentState!.userGestureInProgress, isFalse);
      await unmount(tester);
    }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
  }

  testWidgets('无动画按钮返回立即完成', (tester) async {
    final key = await mount(tester, PageTransitionStyle.none);
    key.currentState!.pop();
    await tester.pump();
    expect(find.text('detail'), findsNothing);
    expect(find.text('home'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('默认动画不引入自定义整页淡化或缩放', (tester) async {
    await mount(tester, PageTransitionStyle.cupertino);
    expect(ancestor(FadeTransition), findsNothing);
    expect(ancestor(ScaleTransition), findsNothing);
    await unmount(tester);
  });

  testWidgets('默认自定义路由保留原Hero专属淡入', (tester) async {
    await mount(tester, PageTransitionStyle.cupertino, customRoute: true, settle: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(ancestor(CupertinoPageTransition), findsNothing);
    expect(tester.widget<FadeTransition>(ancestor(FadeTransition)).opacity.value, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    await unmount(tester);
  });
}
