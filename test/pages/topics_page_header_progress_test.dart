import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/topics_page.dart';

void main() {
  test('quantizeMobileHeaderProgress only flips after threshold', () {
    expect(quantizeMobileHeaderProgress(0.0, threshold: 0.6), 0.0);
    expect(quantizeMobileHeaderProgress(0.59, threshold: 0.6), 0.0);
    expect(quantizeMobileHeaderProgress(0.6, threshold: 0.6), 1.0);
    expect(quantizeMobileHeaderProgress(1.0, threshold: 0.6), 1.0);
  });

  test(
    'homeLoadMoreTriggerDistance prefetches before the footer is reached',
    () {
      expect(homeLoadMoreTriggerDistance(320), 720);
      expect(homeLoadMoreTriggerDistance(800), closeTo(1400, 0.001));
      expect(homeLoadMoreTriggerDistance(1400), 1800);
    },
  );

  test('home load-more also accepts a bottom overscroll event', () {
    expect(
      shouldTriggerHomeLoadMore(
        depth: 0,
        isScrollUpdate: false,
        isOverscroll: true,
        extentAfter: 0,
        viewportDimension: 800,
      ),
      isTrue,
    );
    expect(
      shouldTriggerHomeLoadMore(
        depth: 0,
        isScrollUpdate: false,
        isOverscroll: true,
        extentAfter: 2000,
        viewportDimension: 800,
      ),
      isFalse,
    );
  });

  group('homeScrollToTopAction', () {
    test('远距离回顶重建滚动位置而不是跨越变高列表', () {
      expect(
        homeScrollToTopAction(
          currentOffset: 5000,
          minScrollExtent: 0,
          maxScrollExtent: 6000,
          viewportDimension: 800,
        ),
        HomeScrollToTopAction.remount,
      );
    });

    test('距离顶部不超过两个 viewport 时保持短动画', () {
      expect(
        homeScrollToTopAction(
          currentOffset: 1500,
          minScrollExtent: 0,
          maxScrollExtent: 6000,
          viewportDimension: 800,
        ),
        HomeScrollToTopAction.animate,
      );
    });

    test('以实际最小滚动范围计算远距离阈值', () {
      expect(
        homeScrollToTopAction(
          currentOffset: 1701,
          minScrollExtent: 100,
          maxScrollExtent: 6000,
          viewportDimension: 800,
        ),
        HomeScrollToTopAction.remount,
      );
    });

    test('无效几何不执行滚动', () {
      expect(
        homeScrollToTopAction(
          currentOffset: 5000,
          minScrollExtent: 0,
          maxScrollExtent: 6000,
          viewportDimension: 0,
        ),
        HomeScrollToTopAction.none,
      );
    });
  });

  testWidgets('remount 深层变高列表时只构建顶部有限项', (tester) async {
    final controller = ScrollController();
    final listKey = GlobalKey<_ResettableVariableListState>();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 600,
          child: _ResettableVariableList(key: listKey, controller: controller),
        ),
      ),
    );

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    listKey.currentState!.resetBuildCount();

    listKey.currentState!.remountAtTop();
    await tester.pump();

    expect(controller.offset, 0);
    expect(listKey.currentState!.buildCount, lessThan(30));
    expect(find.text('item-0'), findsOneWidget);
  });
}

class _ResettableVariableList extends StatefulWidget {
  const _ResettableVariableList({super.key, required this.controller});

  final ScrollController controller;

  @override
  State<_ResettableVariableList> createState() =>
      _ResettableVariableListState();
}

class _ResettableVariableListState extends State<_ResettableVariableList> {
  int generation = 0;
  int buildCount = 0;

  void resetBuildCount() => buildCount = 0;

  void remountAtTop() {
    setState(() => generation++);
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: homeTopicListPageStorageKey('test', generation),
      controller: widget.controller,
      itemCount: 400,
      itemBuilder: (context, index) {
        buildCount++;
        return SizedBox(
          height: 48 + (index % 5) * 13,
          child: Text('item-$index'),
        );
      },
    );
  }
}
