import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/navigation/pop_passthrough_material_page_route.dart';
import 'package:fluxdo/services/navigation/topic_detail_route.dart';

void main() {
  test('帖子详情 route 启用首页同款横向返回手势', () {
    final route = buildTopicDetailRoute<void>(topicId: 42);

    expect(route, isA<PopPassthroughMaterialPageRoute<void>>());
    expect(
      (route as PopPassthroughMaterialPageRoute<void>)
          .enableHorizontalPopGesture,
      isTrue,
    );
  });
}
