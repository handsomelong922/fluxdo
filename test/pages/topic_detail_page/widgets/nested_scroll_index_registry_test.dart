import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/nested_post_list.dart';

void main() {
  test('树形滚动索引在局部重建时保持稳定', () {
    final registry = NestedScrollIndexRegistry();

    expect(registry.indexFor(10), 0);
    expect(registry.indexFor(20), 1);
    expect(registry.indexFor(10), 0);
    expect(registry.postNumberFor(0), 10);
    expect(registry.postNumberFor(1), 20);
    expect(registry.snapshot(), <int, int>{10: 0, 20: 1});
  });

  test('整棵树重建时可以重新建立紧凑索引', () {
    final registry = NestedScrollIndexRegistry()
      ..indexFor(10)
      ..indexFor(20)
      ..reset();

    expect(registry.indexFor(30), 0);
    expect(registry.postNumberFor(1), isNull);
    expect(registry.snapshot(), <int, int>{30: 0});
  });
}
