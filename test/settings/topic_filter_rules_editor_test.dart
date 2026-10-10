import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/settings/widgets/topic_filter_rules_editor.dart';

void main() {
  Future<GlobalKey<TopicFilterRulesEditorState>> mount(WidgetTester tester, {
    List<String> keywords = const [], List<String> regexPatterns = const [],
  }) async {
    final key = GlobalKey<TopicFilterRulesEditorState>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: TopicFilterRulesEditor(key: key, initialKeywords: keywords,
          initialRegexPatterns: regexPatterns),
    ))));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });
    return key;
  }

  testWidgets('点击长规则完整回填，可编辑并替换而不是追加', (tester) async {
    final original = '^(求助|提问).*${'电脑' * 30}';
    final key = await mount(tester, regexPatterns: [original]);
    await tester.tap(find.byType(InputChip));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, original);
    await tester.enterText(find.byType(TextField), r'^(手机|电脑).*$');
    final result = key.currentState!.collectRules();
    expect(result!.regexPatterns, [r'^(手机|电脑).*$']);
    expect(result.keywords, isEmpty);
  });

  testWidgets('非法正则保留原规则和输入，修复后才能确认', (tester) async {
    final key = await mount(tester, regexPatterns: [r'^AI$']);
    await tester.tap(find.byType(InputChip));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '(');
    expect(key.currentState!.collectRules(), isNull);
    await tester.pump();
    expect(find.text(r'^AI$'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '(');
    expect(tester.widget<TextField>(find.byType(TextField)).decoration!.errorText, isNotNull);
    await tester.enterText(find.byType(TextField), 'GPT');
    expect(key.currentState!.collectRules()!.regexPatterns, ['GPT']);
  });

  testWidgets('旧关键词默认字面模式，确认会包含尚未添加的输入', (tester) async {
    final key = await mount(tester, keywords: ['a.b']);
    await tester.enterText(find.byType(TextField), 'hello world\n第二条');
    final result = key.currentState!.collectRules()!;
    expect(result.keywords, ['a.b', 'hello world', '第二条']);
    expect(result.regexPatterns, isEmpty);
  });

  testWidgets('显式切换正则模式不改写旧关键词，清空会删除所有草稿', (tester) async {
    final key = await mount(tester, keywords: ['a.b']);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '(help|question).*phone');
    final result = key.currentState!.collectRules()!;
    expect(result.keywords, ['a.b']);
    expect(result.regexPatterns, ['(help|question).*phone']);
    await tester.pump();
    await tester.tap(find.text('Clear rules'));
    await tester.pump();
    expect(key.currentState!.collectRules()!.regexPatterns, isEmpty);
    expect(key.currentState!.collectRules()!.keywords, isEmpty);
  });
}
