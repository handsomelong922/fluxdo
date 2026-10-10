import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/providers/message_bus/topic_tracking_providers.dart';
import 'package:fluxdo/providers/topic_list/filter_provider.dart';
import 'package:fluxdo/providers/topic_list/sort_provider.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/widgets/topic/sort_and_tags_bar.dart';
import 'package:fluxdo/widgets/topic/topic_filter_menu.dart';

// 保留真实计数逻辑，避免测试触发预加载请求。
class _Tracking extends TopicTrackingStateNotifier {
  @override
  Map<int, TrackedTopicState> build() => {
    1: const TrackedTopicState(
      topicId: 1,
      highestPostNumber: 1,
      createdInNewPeriod: true,
    ),
    2: const TrackedTopicState(
      topicId: 2,
      highestPostNumber: 3,
      lastReadPostNumber: 1,
      notificationLevel: 2,
    ),
  };
}

Finder _indicatorDots() => find.byWidgetPredicate((widget) {
  if (widget is! Container || widget.child != null) return false;
  final decoration = widget.decoration;
  return decoration is BoxDecoration && decoration.shape == BoxShape.circle;
});

String _label(TopicListFilter filter) {
  final base = filterLabel(filter);
  return switch (filter) {
    TopicListFilter.newTopics => '$base (2)',
    TopicListFilter.unread => '$base (1)',
    _ => base,
  };
}

void main() {
  for (final titleStyle in [true, false]) {
    for (final order in [
      TopicSortOrder.defaultOrder,
      TopicSortOrder.activity,
    ]) {
      for (final currentFilter in TopicListFilter.values) {
        testWidgets('筛选 $currentFilter 标题样式 $titleStyle 排序 $order 无圆点且选项可用', (
          tester,
        ) async {
          // 展开“新话题”子菜单时也让全部筛选项保持可见。
          await tester.binding.setSurfaceSize(const Size(800, 1200));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final selected = <TopicListFilter>[];
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                topicTrackingStateProvider.overrideWith(_Tracking.new),
              ],
              child: TranslationProvider(
                child: MaterialApp(
                  navigatorKey: navigatorKey,
                  home: Scaffold(
                    body: Align(
                      alignment: Alignment.topLeft,
                      child: TopicFilterMenuButton(
                        currentFilter: currentFilter,
                        isLoggedIn: true,
                        onFilterChanged: selected.add,
                        currentSubset: NewSubset.all,
                        onSubsetChanged: (_) {},
                        currentOrder: order,
                        ascending: false,
                        onOrderChanged: (_) {},
                        onToggleAscending: () {},
                        titleStyle: titleStyle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text(_label(currentFilter)), findsOneWidget);
          expect(_indicatorDots(), findsNothing);
          expect(find.byType(Badge), findsNothing);

          // 每一种当前筛选都验证全部选项：包含已选与未选的情况。
          for (final option in TopicListFilter.values) {
            await tester.tap(find.byType(TopicFilterMenuButton));
            await tester.pumpAndSettle();
            final entries = find.byWidgetPredicate(
              (widget) =>
                  widget is PopupMenuItem<Object> &&
                  widget.value is TopicListFilter,
            );
            expect(entries, findsNWidgets(TopicListFilter.values.length));
            expect(_indicatorDots(), findsNothing);
            expect(find.byType(Badge), findsNothing);
            for (final filter in TopicListFilter.values) {
              final entry = find.byWidgetPredicate(
                (widget) =>
                    widget is PopupMenuItem<Object> && widget.value == filter,
              );
              expect(
                find.descendant(of: entry, matching: find.text(_label(filter))),
                findsOneWidget,
              );
              expect(
                find.descendant(
                  of: entry,
                  matching: find.byIcon(Symbols.check_rounded),
                ),
                filter == currentFilter ? findsOneWidget : findsNothing,
              );
            }
            final target = find.byWidgetPredicate(
              (widget) =>
                  widget is PopupMenuItem<Object> && widget.value == option,
            );
            await tester.ensureVisible(target);
            await tester.tap(target);
            await tester.pumpAndSettle();
            expect(selected.last, option);
            expect(tester.takeException(), isNull);
          }
          expect(selected, TopicListFilter.values);
        });
      }
    }
  }
}
