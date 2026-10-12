import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/utils/list_identity_change.dart';
import 'package:fluxdo/widgets/common/anchor_guard_sliver.dart';
import 'package:fluxdo/widgets/common/paged_list_footer.dart';

void main() {
  for (final dragging in [false, true]) {
    testWidgets('分页请求、正则等待和追加保持底边与可见行稳定 dragging=$dragging', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      late StateSetter rebuild;
      var count = 20;
      var loading = false;
      var pending = false;
      var failed = false;
      List<int>? previousIds;
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  final ids = List.generate(count, (index) => index);
                  final change = classifyListIdentityChange(
                    previousIds,
                    ids,
                    identityOf: (id) => id,
                  );
                  if (change == ListIdentityChange.structural ||
                      change == ListIdentityChange.contentChanged) {
                    AnchorGuardSliver.arm();
                  }
                  previousIds = ids;
                  return CustomScrollView(
                    controller: scroll,
                    physics: const ClampingScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.only(top: 80, bottom: 12),
                        sliver: SliverList.builder(
                          itemCount: count + 1,
                          findChildIndexCallback: (key) {
                            if (key == const ValueKey('footer')) return count;
                            return (key as ValueKey<int>).value;
                          },
                          itemBuilder: (context, index) => index == count
                              ? KeyedSubtree(
                                  key: const ValueKey('footer'),
                                  child: PagedListFooter(
                                    hasMore: true,
                                    isLoadingMore: loading || pending,
                                    isLoadMoreFailed: failed,
                                    minContentHeight: 24,
                                    onRetry: () => rebuild(() {
                                      failed = false;
                                      loading = true;
                                    }),
                                  ),
                                )
                              : SizedBox(
                                  key: ValueKey(index),
                                  height: 60,
                                  child: Text('topic $index'),
                                ),
                        ),
                      ),
                      const AnchorGuardSliver(),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      final gesture = dragging
          ? await tester.startGesture(
              tester.getCenter(find.byType(CustomScrollView)),
            )
          : null;
      if (gesture != null) {
        // 保持真实拖动活动，覆盖守卫不参与补偿的分页落地帧。
        await gesture.moveBy(const Offset(0, 24));
        await tester.pump();
        expect(scroll.position.isScrollingNotifier.value, isTrue);
      }
      final pixels = scroll.offset;
      final extent = scroll.position.maxScrollExtent;
      final row = find.byKey(const ValueKey(18));
      final rowTop = tester.getTopLeft(row).dy;
      final rowElement = tester.element(row);
      for (final phase in ['network', 'regex', 'failure', 'retry', 'idle']) {
        rebuild(() {
          loading = phase == 'network' || phase == 'retry';
          pending = phase == 'regex';
          failed = phase == 'failure';
        });
        await tester.pump();
        expect(scroll.position.maxScrollExtent, closeTo(extent, 0.01));
        expect(scroll.offset, closeTo(pixels, 0.01));
        expect(tester.getTopLeft(row).dy, closeTo(rowTop, 0.01));
        expect(tester.element(row), same(rowElement));
        if (phase == 'failure' && !dragging) {
          await tester.tap(
            find.descendant(
              of: find.byType(PagedListFooter),
              matching: find.byType(GestureDetector),
            ),
          );
          await tester.pump();
          expect(failed, isFalse);
          expect(loading, isTrue);
          expect(scroll.position.maxScrollExtent, closeTo(extent, 0.01));
          expect(scroll.offset, closeTo(pixels, 0.01));
        }
      }
      rebuild(() => count += 5);
      await tester.pump();
      expect(scroll.position.maxScrollExtent, greaterThan(extent));
      expect(scroll.offset, closeTo(pixels, 0.01));
      expect(tester.getTopLeft(row).dy, closeTo(rowTop, 0.01));
      expect(tester.element(row), same(rowElement));
      await gesture?.up();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
