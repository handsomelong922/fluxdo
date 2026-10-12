import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/topic_regex_filter_controller.dart';
import 'package:fluxdo/widgets/topic/topic_regex_filter_status.dart';

/// 仅控制提示条的待处理展示；真实正则任务仍使用原控制器和 Isolate。
class _StatusTestController extends TopicRegexFilterController {
  _StatusTestController(super.onChanged);

  bool showPending = false;
  bool pending = false;

  @override
  bool get active => pending || showPending || super.active;

  @override
  bool get isPending => pending || super.isPending;

  @override
  bool get showPendingIndicator => showPending || super.showPendingIndicator;
}

void main() {
  testWidgets('后台状态变化不重建列表，错误始终可编辑与重试', (tester) async {
    late StateSetter rebuild;
    final controller = _StatusTestController(() => rebuild(() {}));
    addTearDown(controller.dispose);
    final scroll = ScrollController();
    const listKey = ValueKey('stable-list');
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return TopicRegexFilterStatus(
                  controller: controller,
                  child: ListView.builder(
                    key: listKey,
                    controller: scroll,
                    itemExtent: 50,
                    itemCount: 100,
                    itemBuilder: (_, index) => Text('$index'),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    scroll.jumpTo(250);
    await tester.pump();
    final element = tester.element(find.byKey(listKey));
    // 待处理 UI 用确定性状态驱动，避免让真实 Isolate 落进 fakeAsync。
    controller.pending = true;
    rebuild(() {});
    await tester.pump();
    expect(find.textContaining('Checking regex filters'), findsNothing);
    expect(tester.element(find.byKey(listKey)), same(element));
    expect(scroll.offset, 250);
    controller.showPending = true;
    rebuild(() {});
    await tester.pump();
    expect(tester.element(find.byKey(listKey)), same(element));
    expect(scroll.offset, 250);
    expect(find.textContaining('Checking regex filters'), findsOneWidget);
    // 创建、启动、等待和清理真实任务均在同一个 real-async 区域完成。
    await tester.runAsync(() async {
      controller.pending = false;
      controller.showPending = false;
      controller.prepare(['['], ['title']);
      await controller.settle(['['], ['title']);
    });
    await tester.pump();
    expect(find.textContaining('Regex filtering failed'), findsOneWidget);
    expect(find.text('Edit rules'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.element(find.byKey(listKey)), same(element));
    expect(scroll.offset, 250);
    controller.prepare([], ['title']);
    rebuild(() {});
    await tester.pump();
    expect(tester.element(find.byKey(listKey)), same(element));
    expect(scroll.offset, 250);
    controller.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
  });
}
