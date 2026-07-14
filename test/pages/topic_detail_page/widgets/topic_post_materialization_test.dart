import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/topic_post_materialization.dart';

void main() {
  test('尾部翻页只为 after 侧创建不小于旧列表的 cap', () {
    final growth = detectTopicPostGrowth(
      oldPostIds: const [1, 2, 3],
      newPostIds: const [1, 2, 3, 4, 5],
    );
    final plan = planTopicPostPagingMaterialization(
      growth: growth,
      oldSegmentCount: 12,
      newSegmentCount: 22,
      oldCenterScrollIndex: 3,
    );

    expect(growth, TopicPostGrowth.append);
    expect(plan?.side, TopicPostMaterializationSide.after);
    expect(plan?.initialCap, 13); // 旧 after 9 段 + 4
  });

  test('头部翻页只为 before 侧创建不小于旧列表的 cap', () {
    final growth = detectTopicPostGrowth(
      oldPostIds: const [3, 4, 5],
      newPostIds: const [1, 2, 3, 4, 5],
    );
    final plan = planTopicPostPagingMaterialization(
      growth: growth,
      oldSegmentCount: 12,
      newSegmentCount: 22,
      oldCenterScrollIndex: 7,
    );

    expect(growth, TopicPostGrowth.prepend);
    expect(plan?.side, TopicPostMaterializationSide.before);
    expect(plan?.initialCap, 11); // 旧 before 7 段 + 4
  });

  test('gap 填充、整页替换和少量新增不启动分页 cap', () {
    expect(
      detectTopicPostGrowth(
        oldPostIds: const [1, 3],
        newPostIds: const [1, 2, 3],
      ),
      isNull,
    );
    expect(
      detectTopicPostGrowth(
        oldPostIds: const [1, 2],
        newPostIds: const [3, 4, 5],
      ),
      isNull,
    );

    final smallGrowth = detectTopicPostGrowth(
      oldPostIds: const [1, 2],
      newPostIds: const [1, 2, 3],
    );
    expect(
      planTopicPostPagingMaterialization(
        growth: smallGrowth,
        oldSegmentCount: 4,
        newSegmentCount: 7,
        oldCenterScrollIndex: 0,
      ),
      isNull,
    );
  });

  test('首屏 after cap 会完整包含长 center 帖子和近邻段', () {
    final cap = initialAfterMaterializationCap(
      segmentPostIds: const [10, 10, 10, 10, 10, 10, 11, 12, 13, 14, 15],
      centerScrollIndex: 0,
    );

    expect(cap, 10); // center 的 6 段 + 4 个近邻段
  });

  test('中心切换后的初始 cap 保持有界并完整包含新中心长帖', () {
    final plan = initialTopicPostMaterialization(
      segmentPostIds: const [1, 2, 20, 20, 20, 20, 3, 4, 5, 6, 7, 8],
      centerScrollIndex: 2,
    );

    expect(plan.beforeCap, 4);
    expect(plan.afterCap, 8); // center 的 4 段 + 4 个近邻段
    expect(plan.beforeCap, lessThan(12));
    expect(plan.afterCap, lessThan(12));
  });

  test('materialized count 不超过总数且不接受负 cap', () {
    expect(materializedSegmentCount(total: 20, cap: null), 20);
    expect(materializedSegmentCount(total: 20, cap: 8), 8);
    expect(materializedSegmentCount(total: 5, cap: 8), 5);
    expect(materializedSegmentCount(total: 5, cap: -1), 0);
  });

  test('主动滚动期间暂停渐进物化，结束后继续', () {
    expect(
      shouldAdvanceTopicPostMaterialization(
        isScrollActive: true,
        hasPendingMaterialization: true,
      ),
      isFalse,
    );
    expect(
      shouldAdvanceTopicPostMaterialization(
        isScrollActive: false,
        hasPendingMaterialization: true,
      ),
      isTrue,
    );
    expect(
      shouldAdvanceTopicPostMaterialization(
        isScrollActive: false,
        hasPendingMaterialization: false,
      ),
      isFalse,
    );
  });

  test('prepend 平移 center 索引不视为显式换中心', () {
    expect(
      didTopicPostCenterChange(
        oldPostNumbers: const [10, 11, 12],
        oldCenterPostIndex: 1,
        newPostNumbers: const [8, 9, 10, 11, 12],
        newCenterPostIndex: 3,
      ),
      isFalse,
    );
  });

  test('同话题显式更换 center 时识别为中心变化', () {
    expect(
      didTopicPostCenterChange(
        oldPostNumbers: const [10, 11, 12],
        oldCenterPostIndex: 0,
        newPostNumbers: const [10, 11, 12],
        newCenterPostIndex: 2,
      ),
      isTrue,
    );
  });
}
