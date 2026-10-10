import 'package:common_ui/common_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/personal_navigation_preferences_provider.dart';
import 'package:fluxdo/widgets/common/fullscreen_swipe_back.dart';
import 'package:fluxdo/widgets/common/personal_page_transitions.dart';

var _mounts = 0;
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
  Future<GlobalKey<NavigatorState>> mount(WidgetTester tester, PageTransitionStyle style, {bool fullscreen = false}) async {
    _mounts = 0;
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      theme: ThemeData(pageTransitionsTheme: personalPageTransitionsTheme(style: style, fullscreenSwipeBack: fullscreen)),
      home: const Scaffold(body: Text('home')),
    ));
    key.currentState!.push(MaterialPageRoute<void>(builder: (_) => const _Detail()));
    await tester.pumpAndSettle();
    return key;
  }

  test('默认逐平台保留原builder；全屏手势只是装饰器', () {
    final normal = personalPageTransitionsTheme(style: PageTransitionStyle.cupertino, fullscreenSwipeBack: false);
    expect(normal.builders[TargetPlatform.android], isA<PredictiveBackCupertinoPageTransitionsBuilder>());
    expect(normal.builders[TargetPlatform.iOS], isA<CupertinoPageTransitionsBuilder>());
    final full = personalPageTransitionsTheme(style: PageTransitionStyle.cupertino, fullscreenSwipeBack: true);
    expect(full.builders[TargetPlatform.iOS], isA<FullscreenSwipeBackTransitionsBuilder>());
  });

  for (final style in PageTransitionStyle.values) {
    testWidgets('${style.name} 系统预测返回取消/提交，正文只挂载一次', (tester) async {
      final key = await mount(tester, style);
      await send('startBackGesture', 0);
      await tester.pump();
      await send('updateBackGestureProgress', .5);
      await tester.pump();
      expect(tester.getTopLeft(find.text('detail')).dx, greaterThan(0));
      await send('cancelBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);
      expect(key.currentState!.userGestureInProgress, isFalse);
      expect(_mounts, 1);
      await send('startBackGesture', 0);
      await tester.pump();
      await send('updateBackGestureProgress', .6);
      await tester.pump();
      await send('commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(find.text('detail'), findsNothing);
      expect(key.currentState!.userGestureInProgress, isFalse);
      expect(_mounts, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    }, variant: const TargetPlatformVariant({TargetPlatform.android}));

    testWidgets('${style.name} 全屏返回取消/提交，正文不重建', (tester) async {
      final key = await mount(tester, style, fullscreen: true);
      final cancel = await tester.startGesture(const Offset(200, 300));
      await cancel.moveBy(const Offset(110, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await cancel.up();
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);
      expect(_mounts, 1);
      final commit = await tester.startGesture(const Offset(200, 300));
      await commit.moveBy(const Offset(480, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await commit.up();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(key.currentState!.userGestureInProgress, isFalse);
      expect(_mounts, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
  }

  testWidgets('无动画按钮返回立即完成', (tester) async {
    final key = await mount(tester, PageTransitionStyle.none);
    key.currentState!.pop();
    await tester.pump();
    expect(find.text('detail'), findsNothing);
    expect(find.text('home'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('默认动画不引入自定义整页淡化或缩放', (tester) async {
    await mount(tester, PageTransitionStyle.cupertino);
    expect(find.ancestor(of: find.text('detail'), matching: find.byType(FadeTransition)), findsNothing);
    expect(find.ancestor(of: find.text('detail'), matching: find.byType(ScaleTransition)), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
