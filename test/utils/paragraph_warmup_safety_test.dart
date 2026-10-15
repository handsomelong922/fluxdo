import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/fluxdo_render.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/utils/paragraph_warmup_safety.dart';
import 'package:fluxdo/widgets/post/post_item/render_parse_cache.dart';

import '../../tool/render_warmup_slice_smoke.dart';

void main() {
  setUp(() {
    FlattenCache.evictAll();
    ParagraphLayoutCache.evictAll();
    ParagraphWarmupProbe.reset();
    RenderParseCache.clear();
  });

  test('短帖和长帖游标保留渲染块边界', runRenderWarmupSliceChecks);

  test('交互节点及其父节点不进入无回调预热', () {
    final nodes = ParagraphParser()
        .parse(
          '<p>纯文字 <strong><em>粗斜体</em></strong><br>换行</p>'
          '<p><strong><a href="https://example.com">链接</a></strong></p>'
          '<p><img src="/a.png" width="100" height="50"></p>'
          '<p><code>代码</code></p>',
        )
        .whereType<ParagraphNode>()
        .toList();
    expect(nodes.first.inlines.every(canWarmInlineWithoutCallbacks), isTrue);
    for (final node in nodes.skip(1)) {
      expect(node.inlines.every(canWarmInlineWithoutCallbacks), isFalse);
    }
  });

  testWidgets('带图块的纯文预热命中；图片数、样式、主题及节点变化失效', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FluxdoRender(cookedHtml: '<p>用于取得真实挂载环境的正文</p>')),
      ),
    );
    final context = tester.element(find.byType(FluxdoRender));
    final snapshot = ParagraphWarmupProbe.snapshot()!;
    final nodes = ParagraphParser().parse(
      '<p>待预热正文</p><p><img src="/a.png" width="100" height="50"></p>',
    );
    expect(countImageRuns(nodes), 1);
    expect(
      warmSafeParagraphs(
        nodes: nodes,
        ctx: snapshot,
        context: context,
        budgetMicros: 1 << 30,
      ),
      -1,
    );
    final paragraph = nodes.whereType<ParagraphNode>().first;
    var created = 0;
    void acquire({
      List<InlineNode>? inlines,
      TextStyle? style,
      ThemeData? theme,
      int images = 1,
    }) {
      final result = FlattenCache.acquire(
        inlines: inlines ?? paragraph.inlines,
        baseStyle: style ?? snapshot.baseStyle,
        theme: theme ?? snapshot.theme,
        totalImagesInPost: images,
        flattener: snapshot.flattener,
        create: () {
          created++;
          return snapshot.flattener.flatten(
            inlines ?? paragraph.inlines,
            style ?? snapshot.baseStyle,
            totalImagesInPost: images,
            context: context,
          );
        },
      );
      FlattenCache.release(result);
    }

    acquire();
    expect(created, 0, reason: '与挂载端相同的块内图片数命中');
    acquire(images: 0);
    acquire(style: snapshot.baseStyle.copyWith(fontSize: 30));
    acquire(theme: ThemeData.dark());
    acquire(inlines: List<InlineNode>.of(paragraph.inlines));
    expect(created, 4, reason: '四种渲染条件变化分别失效');

    // 链接段落不得以默认 handler 抢先写入缓存；真实挂载仍执行自己的 create。
    final links = ParagraphParser().parse('<p><a href="/t/1">点击</a></p>');
    warmSafeParagraphs(nodes: links, ctx: snapshot, context: context);
    final link = links.whereType<ParagraphNode>().first;
    acquire(inlines: link.inlines, images: 0);
    expect(created, 5, reason: '交互缓存必须由携带真实回调的挂载端创建');
  });

  testWidgets('极小预算重复调用必须前进并最终结束', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FluxdoRender(cookedHtml: '<p>探针正文</p>')),
      ),
    );
    final context = tester.element(find.byType(FluxdoRender));
    final snapshot = ParagraphWarmupProbe.snapshot()!;
    final nodes = ParagraphParser().parse(
      '<p>第一段</p><p><a href="/t/1">跳过链接</a></p>'
      '<p>第二段</p><p>第三段</p>',
    );
    for (final budget in [0, 1]) {
      var cursor = 0;
      var calls = 0;
      while (cursor != -1 && calls <= nodes.length) {
        final previous = cursor;
        cursor = warmSafeParagraphs(
          nodes: nodes,
          ctx: snapshot,
          context: context,
          startIndex: cursor,
          budgetMicros: budget,
        );
        expect(
          cursor == -1 || cursor > previous,
          isTrue,
          reason: '预算不足不得在相同游标反复调度',
        );
        calls++;
      }
      expect(cursor, -1);
      expect(calls, lessThanOrEqualTo(nodes.length));
    }
  });

  test('图片尺寸和正文修改使解析身份失效，原内容命中', () {
    Post post(String cooked) => Post(
      id: 912,
      username: 'test',
      avatarTemplate: '',
      cooked: cooked,
      postNumber: 1,
      postType: 1,
      updatedAt: DateTime.utc(2026),
      createdAt: DateTime.utc(2026),
      likeCount: 0,
      replyCount: 0,
    );
    final initial = post('<p>正文<img src="/a.png" width="100" height="50"></p>');
    final first = RenderParseCache.shortPost(initial).nodes;
    expect(identical(first, RenderParseCache.shortPost(initial).nodes), isTrue);
    final resized = post('<p>正文<img src="/a.png" width="200" height="50"></p>');
    expect(
      RenderParseCache.signatureOf(initial),
      isNot(RenderParseCache.signatureOf(resized)),
    );
    final second = RenderParseCache.shortPost(resized).nodes;
    expect(identical(first, second), isFalse);
    expect(
      identical(second, RenderParseCache.shortPost(resized).nodes),
      isTrue,
    );
    final edited = post('<p>修改后的正文</p>');
    expect(
      identical(second, RenderParseCache.shortPost(edited).nodes),
      isFalse,
    );
  });
}
