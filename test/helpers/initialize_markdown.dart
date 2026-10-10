import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/discourse_cook_service.dart';
import 'package:fluxdo/services/preloaded_data_service.dart';

/// MarkdownBody 直接使用 cook/preload 单例，不能仅靠 Riverpod 覆写隔离。
/// 先恢复本地引导数据并等待真实初始化，避免挂载时请求首页及产生调度计时器。
Future<void> initializeMarkdownFixture(WidgetTester tester) async {
  await tester.runAsync(() async {
    final preloaded = PreloadedDataService();
    final loaded = await preloaded.hydrateFromHtml(
      '<meta id="data-discourse-setup">'
      '<script id="data-preloaded" type="application/json">${jsonEncode({
        'currentUser': {'id': 1, 'username': 'tester'},
        'siteSettings': {'min_post_length': 1, 'max_post_length': 10000},
        'site': {'categories': [], 'top_tags': []},
      })}</script>',
    );
    expect(loaded, isTrue);
    expect(preloaded.isLoaded, isTrue);
    // 原生 JS 不可用时允许组件使用正式的 Dart Markdown 降级渲染。
    // 两条路径均保留真实组件；不替换输出，也不屏蔽网络或计时器断言。
    await DiscourseCookService().ensureInitialized();
  });
  addTearDown(() => PreloadedDataService().reset());
}
