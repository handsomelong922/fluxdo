import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/navigation/horizontal_pop_gesture_blocker.dart';
import 'package:fluxdo/services/navigation/pop_passthrough_material_page_route.dart';
import 'package:fluxdo/services/navigation/topic_detail_route.dart';
import 'package:fluxdo/widgets/post/post_item/quote_selection_helper.dart';

void main() {
  test('帖子详情 route 启用首页同款横向返回手势', () {
    final route = buildTopicDetailRoute<void>(topicId: 42);

    expect(route, isA<PopPassthroughMaterialPageRoute<void>>());
    final topicRoute = route as PopPassthroughMaterialPageRoute<void>;
    expect(topicRoute.enableHorizontalPopGesture, isTrue);
    expect(
      topicRoute.horizontalPopGestureBlocker,
      same(QuoteSelectionHelper.selectionActiveListenable),
    );
    expect(
      topicRoute.additionalHorizontalPopGestureBlocker,
      same(HorizontalPopGestureBlocker.activeListenable),
    );
  });
}
