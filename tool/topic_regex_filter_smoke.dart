import 'dart:async';

import '../lib/utils/topic_regex_filter_controller.dart';

/// 用真实工作隔离区验证列表控制器的缓存、分页和生命周期。
final topicRegexFilterSmokeTests = <String, Future<void> Function()>{
  '短任务及连续分页不立即显示正则提示，未知标题仍隐藏': () async {
    var changes = 0;
    final controller = TopicRegexFilterController(() => changes++);
    try {
      final titles = <String>[];
      for (var page = 0; page < 5; page++) {
        titles.add('title $page');
        controller.prepare(['hide'], titles);
        _check(controller.isPending, '任务必须立即进入安全待验证状态');
        _check(!controller.showPendingIndicator, '短批次不能立即闪现提示条');
        _check(!controller.matches.containsKey(titles.last), '新标题不能提前显示');
        _check(await controller.settle(['hide'], titles), '分页应成功');
        _check(!controller.showPendingIndicator, '完成后不能保留提示');
      }
      final settledChanges = changes;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _check(changes == settledChanges, '完成后不能残留提示计时器通知');
    } finally {
      controller.dispose();
    }
  },
  '长任务延迟显示，取消和换代清理提示计时器': () async {
    var changes = 0;
    final controller = TopicRegexFilterController(() => changes++);
    try {
      final old = controller.settle([r'^(a+)+$'], ['${'a' * 20000}!']);
      _check(!controller.showPendingIndicator, '任务启动不能立即显示提示');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _check(
        controller.isPending && controller.showPendingIndicator,
        '长任务应显示提示',
      );
      _check(changes == 1, '提示出现应通知界面');
      controller.prepare(['fresh'], ['fresh']);
      _check(!controller.showPendingIndicator, '换代不能继承旧提示');
      _check(!await old, '旧任务应取消');
      await controller.settle(['fresh'], ['fresh']);
      final settledChanges = changes;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _check(changes == settledChanges, '旧提示计时器不得回写');
    } finally {
      controller.dispose();
    }
  },
  '长任务超时保留明确错误，重试重新等待提示延迟': () async {
    final controller = TopicRegexFilterController(() {});
    try {
      final patterns = [r'^(a+)+$'];
      final titles = ['${'a' * 20000}!'];
      _check(!await controller.settle(patterns, titles), '灾难回溯应超时失败');
      _check(controller.error?.message == 'timeout', '必须保留超时错误');
      _check(
        !controller.isPending && !controller.showPendingIndicator,
        '失败后清除待处理提示',
      );
      _check(controller.matches.isEmpty, '失败标题不能标记为安全');
      controller.retry();
      _check(controller.error == null && controller.isPending, '显式重试应启动新任务');
      _check(!controller.showPendingIndicator, '重试必须重新等待展示延迟');
      controller.prepare([], []);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _check(!controller.showPendingIndicator, '取消重试不能留下提示');
    } finally {
      controller.dispose();
    }
  },
  '旧任务计时器不能使新任务提前显示提示': () async {
    final controller = TopicRegexFilterController(() {});
    try {
      final old = controller.settle([r'^(a+)+$'], ['${'a' * 20000}!']);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final next = controller.settle([r'^(b+)+$'], ['${'b' * 20000}!']);
      _check(!await old, '换代应取消旧任务');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      _check(
        controller.isPending && !controller.showPendingIndicator,
        '旧任务到时不能提前亮起新提示',
      );
      controller.prepare([], []);
      _check(!await next, '清空规则应取消新任务');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      _check(!controller.showPendingIndicator, '清空规则必须取消提示计时器');
    } finally {
      controller.dispose();
    }
  },
  '销毁待处理任务会取消尚未显示的提示通知': () async {
    var changes = 0;
    final controller = TopicRegexFilterController(() => changes++);
    final pending = controller.settle([r'^(a+)+$'], ['${'a' * 20000}!']);
    controller.dispose();
    await pending;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _check(changes == 0 && !controller.showPendingIndicator, '销毁后不能出现迟到提示');
  },
  '首次待处理时未知标题没有缓存，完成后缓存全部布尔结果': () async {
    var changes = 0;
    final controller = TopicRegexFilterController(() => changes++);
    try {
      controller.prepare(['^hide\$'], ['hide', 'show']);
      _check(controller.active, '存在规则时应处于启用状态');
      _check(controller.isPending, '首次批次应处于待处理状态');
      _check(controller.matches.isEmpty, '未知标题不能预先标记为可见或已命中');
      _check(await controller.settle(['^hide\$'], ['hide', 'show']), '批次应成功');
      _check(!controller.isPending, '完成后应清除待处理状态');
      _check(controller.matches['hide'] == true, '命中应缓存 true');
      _check(controller.matches['show'] == false, '不命中应缓存 false');
      _check(changes >= 1, '完成批次应通知界面');
      final settledChanges = changes;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _check(changes == settledChanges, '完成后不能再发提示通知');
    } finally {
      controller.dispose();
    }
  },
  '相同输入的重建不重复启动任务或通知': () async {
    var changes = 0;
    final controller = TopicRegexFilterController(() => changes++);
    try {
      final pending = controller.settle(['^hide\$'], ['hide', 'show']);
      for (var i = 0; i < 10; i++) {
        controller.prepare(['^hide\$'], ['hide', 'show']);
      }
      _check(await pending, '相同输入不应取消当前批次');
      final settledChanges = changes;
      for (var i = 0; i < 10; i++) {
        controller.prepare(['^hide\$'], ['hide', 'show']);
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      _check(!controller.isPending && changes == settledChanges, '已缓存输入不应再次运算');
    } finally {
      controller.dispose();
    }
  },
  '分页保留旧缓存，新标题在异步完成前维持未知': () async {
    final controller = TopicRegexFilterController(() {});
    try {
      _check(
        await controller.settle(['hide'], ['hide old', 'show old']),
        '首批应成功',
      );
      controller.prepare(
        ['hide'],
        ['hide old', 'show old', 'hide new', 'show new'],
      );
      _check(controller.matches.length == 2, '分页不应清空已确认的旧标题');
      _check(controller.matches['hide old'] == true, '旧命中应保留');
      _check(controller.matches['show old'] == false, '旧未命中应保留');
      _check(!controller.matches.containsKey('hide new'), '新标题应保持未知');
      _check(controller.isPending, '新增标题需要等待');
      _check(
        await controller.settle(
          ['hide'],
          ['hide old', 'show old', 'hide new', 'show new'],
        ),
        '分页批次应成功',
      );
      _check(controller.matches.length == 4, '新增结果应合并到缓存');
      _check(
        controller.matches['hide new'] == true &&
            controller.matches['show new'] == false,
        '新增标题的结果应正确',
      );
    } finally {
      controller.dispose();
    }
  },
  '刷新删除的标题立即清出缓存，重复标题只缓存一份': () async {
    var changes = 0;
    final controller = TopicRegexFilterController(() => changes++);
    try {
      await controller.settle(['hide'], ['hide', 'show', 'gone']);
      final settledChanges = changes;
      controller.prepare(['hide'], ['hide', 'hide', 'show']);
      _check(controller.matches.length == 2, '删除的标题应清理');
      _check(!controller.matches.containsKey('gone'), '不能留下失效标题缓存');
      _check(!controller.isPending, '已有缓存的刷新不需重新运算');
      _check(changes == settledChanges, '仅清理缓存不应额外发异步通知');
      controller.prepare(['hide'], []);
      _check(controller.matches.isEmpty && !controller.isPending, '空列表应清空缓存');
    } finally {
      controller.dispose();
    }
  },
  '更换规则取消旧任务，旧结果不覆盖新一代缓存': () async {
    var changes = 0;
    final controller = TopicRegexFilterController(() => changes++);
    try {
      final old = controller.settle([r'^(a+)+$'], ['${'a' * 20000}!']);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      controller.prepare(['^fresh\$'], ['fresh', 'other']);
      _check(controller.matches.isEmpty && controller.isPending, '新规则应清空旧缓存');
      _check(!await old, '被替代的旧批次必须返回未成功');
      _check(
        await controller.settle(['^fresh\$'], ['fresh', 'other']),
        '新批次应成功',
      );
      _check(controller.matches.length == 2, '旧标题不能写回缓存');
      _check(
        controller.matches['fresh'] == true &&
            controller.matches['other'] == false,
        '只能保留新规则的结果',
      );
      final settledChanges = changes;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _check(changes == settledChanges, '旧取消批次不能再触发通知');
    } finally {
      controller.dispose();
    }
  },
  '坏规则异步失败，重建和分页不重试，修改后恢复': () async {
    var changes = 0;
    final controller = TopicRegexFilterController(() => changes++);
    try {
      _check(!await controller.settle(['['], ['one']), '坏规则应报告失败');
      _check(controller.error?.message == 'syntax', '应暴露明确语法错误');
      _check(changes >= 1 && !controller.isPending, '失败批次应通知并结束待处理状态');
      final settledChanges = changes;
      for (var i = 0; i < 10; i++) {
        controller.prepare(['['], ['one']);
      }
      controller.prepare(['['], ['one', 'two']);
      _check(!await controller.settle(['['], ['one', 'two']), '新增标题不能隐式重试坏规则');
      _check(
        changes == settledChanges && !controller.isPending,
        '滚动重建不能反复执行失败规则',
      );
      _check(await controller.settle(['^two\$'], ['one', 'two']), '修改规则后应恢复');
      _check(controller.error == null, '修改规则应清除旧错误');
      _check(
        controller.matches['one'] == false && controller.matches['two'] == true,
        '恢复后应使用新规则',
      );
    } finally {
      controller.dispose();
    }
  },
  '同步资源检查错误也通过任务结果报告，不使 prepare 抛错': () async {
    final controller = TopicRegexFilterController(() {});
    try {
      controller.prepare(List.filled(33, 'a'), ['a']);
      _check(!await controller.settle(List.filled(33, 'a'), ['a']), '数量越界必须失败');
      _check(controller.error?.message == 'count', '应保留 count 类别');
      _check(controller.matches.isEmpty, '失败不能留下部分结果');
    } finally {
      controller.dispose();
    }
  },
  '标题资源越界明确失败，不截断，不在重建时重试': () async {
    final controller = TopicRegexFilterController(() {});
    try {
      final titles = List.generate(16385, (i) => 'title $i');
      controller.prepare(['title'], titles);
      _check(controller.error?.message == 'titles', '超量标题应明确失败');
      _check(
        !controller.isPending && controller.matches.isEmpty,
        '不能匹配截断后的标题列表',
      );
      controller.prepare(['title'], ['title']);
      _check(
        controller.error?.message == 'titles' && !controller.isPending,
        '失败应保持直到显式恢复',
      );
      _check(await controller.settle(['^title\$'], ['title']), '修改规则后应恢复');
    } finally {
      controller.dispose();
    }
  },
  '清空规则会取消待处理任务并恢复无过滤状态': () async {
    var changes = 0;
    final controller = TopicRegexFilterController(() => changes++);
    try {
      final old = controller.settle([r'^(a+)+$'], ['${'a' * 20000}!']);
      controller.prepare([], ['anything']);
      _check(!controller.active && !controller.isPending, '清空后不应继续过滤或等待');
      _check(controller.matches.isEmpty && controller.error == null, '规则状态应清空');
      _check(!await old, '旧任务应取消');
      _check(await controller.settle([], ['anything']), '无规则无需等待');
      _check(changes == 0, '已取消任务不能额外通知');
    } finally {
      controller.dispose();
    }
  },
  'dispose 取消工作、清空状态，后续 prepare 或 retry 都不再通知': () async {
    var changes = 0;
    final controller = TopicRegexFilterController(() => changes++);
    final pending = controller.settle([r'^(a+)+$'], ['${'a' * 20000}!']);
    controller.dispose();
    controller.dispose();
    _check(!await pending, '销毁的待处理任务不能成功');
    _check(!controller.isPending && controller.matches.isEmpty, '销毁后不能保留待处理状态');
    controller.prepare(['a'], ['a']);
    controller.retry();
    _check(!await controller.settle(['a'], ['a']), '已销毁控制器不可恢复');
    _check(changes == 0, '销毁之后不允许发出状态通知');
  },
};

Future<void> main() async {
  var passed = 0;
  for (final entry in topicRegexFilterSmokeTests.entries) {
    await entry.value();
    passed++;
    print('PASS ${entry.key}');
  }
  print('$passed 个过滤控制器烟雾测试全部通过');
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}
