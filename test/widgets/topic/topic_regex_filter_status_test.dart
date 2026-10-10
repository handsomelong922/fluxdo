import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/topic_regex_filter_controller.dart';
import 'package:fluxdo/widgets/topic/topic_regex_filter_status.dart';

void main() {
  testWidgets('后台状态变化不重建列表，错误始终可编辑与重试', (tester) async {
    late StateSetter rebuild;
    final controller = TopicRegexFilterController(() => rebuild(() {}));
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
    controller.prepare(['['], ['title']);
    rebuild(() {});
    await tester.pump();
    expect(tester.element(find.byKey(listKey)), same(element));
    expect(scroll.offset, 250);
    await tester.runAsync(() => controller.settle(['['], ['title']));
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
