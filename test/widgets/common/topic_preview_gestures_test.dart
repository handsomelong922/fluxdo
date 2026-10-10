import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/widgets/common/topic_preview_gestures.dart';

void main() {
  var opened = 0;
  var previewed = 0;
  var childTapped = 0;
  const card = Key('card');
  Future<void> mount(WidgetTester tester, {bool right = false, bool long = true, bool available = true}) async {
    opened = previewed = childTapped = 0;
    SharedPreferences.setMockInitialValues({'pref_right_edge_tap_preview': right});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(home: Scaffold(body: Center(child: SizedBox(
        width: 400,
        height: 100,
        child: TopicPreviewGestures(
          bottomGap: 0,
          onTap: () => opened++,
          onPreview: available ? (_) => previewed++ : null,
          enableLongPress: long,
          builder: (context, onTap, onLongPress) => GestureDetector(
            key: card,
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onLongPress: onLongPress,
            child: Align(alignment: Alignment.topRight, child: SizedBox(
              width: 50, height: 35,
              child: TextButton(onPressed: () => childTapped++, child: const Text('子')),
            )),
          ),
        ),
      )))),
    ));
  }
  Offset point(WidgetTester tester, double x, [double y = 70]) => tester.getTopLeft(find.byKey(card)) + Offset(x, y);

  testWidgets('默认右侧正常打开，长按仍预览', (tester) async {
    await mount(tester);
    await tester.tapAt(point(tester, 350));
    await tester.longPressAt(point(tester, 200));
    expect(opened, 1);
    expect(previewed, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
  testWidgets('右侧25%精确边界及长按独立关闭', (tester) async {
    await mount(tester, right: true, long: false);
    await tester.tapAt(point(tester, 299));
    await tester.tapAt(point(tester, 300));
    await tester.tapAt(point(tester, 399));
    expect(opened, 1);
    expect(previewed, 2);
    await tester.longPressAt(point(tester, 200));
    expect(previewed, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
  testWidgets('两个开关同时开启，子按钮和拖动不被右区劫持', (tester) async {
    await mount(tester, right: true);
    await tester.tapAt(point(tester, 350));
    await tester.longPressAt(point(tester, 200));
    await tester.tap(find.text('子'));
    await tester.dragFrom(point(tester, 350), const Offset(0, -70));
    expect(previewed, 2);
    expect(childTapped, 1);
    expect(opened, 0);
    // 原卡片回调可由键盘/语义触发，不应沿用子按钮的右区落点。
    tester.widget<GestureDetector>(find.byKey(card)).onTap!();
    expect(opened, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
  testWidgets('不能预览和两个开关关闭均正常打开', (tester) async {
    await mount(tester, right: true, available: false);
    await tester.tapAt(point(tester, 350));
    expect(opened, 1);
    expect(previewed, 0);
    await tester.pumpWidget(const SizedBox());
    await mount(tester, right: false, long: false);
    await tester.tapAt(point(tester, 350));
    expect(opened, 1);
    expect(previewed, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
