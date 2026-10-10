import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: deprecated_member_use
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/app_localizations.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/ai_post_review_provider.dart';
import 'package:fluxdo/providers/ai_topic_summary_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/ai_topic_summary_service.dart';
import 'package:fluxdo/widgets/ai/ai_topic_summary_sheet.dart';
import 'package:fluxdo/widgets/common/relative_time_text.dart';
import 'package:fluxdo/widgets/markdown_editor/markdown_renderer.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _account = StateProvider<String>((ref) => 'site:42');
final _model = (
  provider: AiProvider(
    id: 'mock',
    name: 'Mock AI',
    type: AiProviderType.openai,
    baseUrl: 'https://example.invalid',
    models: const [AiModel(id: 'mock-model')],
  ),
  model: const AiModel(id: 'mock-model'),
);
TopicDetail _detail({bool privateMessage = false}) => TopicDetail.fromJson({
  'id': 1,
  'title': '测试话题',
  'slug': 'test',
  'posts_count': 1,
  'post_stream': {
    'posts': [],
    'stream': [1],
  },
  'category_id': 0,
  'archetype': privateMessage ? 'private_message' : 'regular',
});
AiTopicSummaryService _service(Future<String> Function() generate) =>
    AiTopicSummaryService(
      loadTopic: () async =>
          const SummarySnapshot('标题', [1], [SummaryPost(1, 1, '用户', '主帖')]),
      loadPosts: (_) async => [],
      generate: (_, _, _) => generate(),
    );

Future<SharedPreferences> _pump(
  WidgetTester tester, {
  AiTopicSummaryService? service,
  double textScale = 1,
  ValueNotifier<bool>? visible,
  bool privateMessage = false,
  void Function(String)? onContinue,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  Widget body() => SingleChildScrollView(
    child: AiTopicSummaryButton(
      detail: _detail(privateMessage: privateMessage),
      headerExtra: const Text('常规'),
      onContinueConversation: onContinue,
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        aiSharedPreferencesProvider.overrideWithValue(prefs),
        aiTopicSummaryAccountProvider.overrideWith(
          (ref) => ref.watch(_account),
        ),
        aiTopicSummaryResolvedModelProvider(1)
            .overrideWithValue(service == null ? null : _model),
        aiPostReviewAvailableModelsProvider.overrideWithValue(
          service == null ? [] : [_model],
        ),
        aiTopicSummaryApiKeyLoaderProvider.overrideWithValue(
          (_) async => 'mock-key',
        ),
        aiTopicSummaryDefaultPromptProvider.overrideWithValue('内置总结要求'),
        if (service != null)
          aiTopicSummaryServiceFactoryProvider.overrideWithValue(
            ({
              required topicId,
              required provider,
              required model,
              required apiKey,
            }) => service,
          ),
      ],
      child: TranslationProvider(
        child: MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocaleUtils.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: visible == null
                ? body()
                : ValueListenableBuilder<bool>(
                    valueListenable: visible,
                    builder: (_, show, _) => show ? body() : const Text('另一页'),
                  ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return prefs;
}

Future<void> _expand(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('ai-summary-toggle')));
  await tester.pump();
  await tester.pump();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void main() {
  testWidgets('未配置模型时内联引导设置，只有一个摘要入口，无底部面板', (tester) async {
    await _pump(tester);
    expect(find.text('AI 摘要'), findsOneWidget);
    expect(find.byType(AiTopicSummaryCard), findsNothing);
    await _expand(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('尚未配置文本模型'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-summary-card')), findsOneWidget);
    final start = tester.widget<TextButton>(
      find.byKey(const ValueKey('ai-summary-refresh')),
    );
    expect(start.onPressed, isNull);
    await tester.tap(find.text('模型设置'));
    await tester.pumpAndSettle();
    expect(find.byType(AiProvidersPage), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('Prompt 保存、恢复内置、折叠重开后仍保留', (tester) async {
    final prefs = await _pump(tester);
    await _expand(tester);
    await tester.tap(find.text('总结 Prompt'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '重点总结技术争议和楼层');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(prefs.getString(topicSummaryPromptKey), '重点总结技术争议和楼层');
    await _expand(tester);
    await _expand(tester);
    await tester.tap(find.text('总结 Prompt'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '重点总结技术争议和楼层',
    );
    await tester.tap(find.text('恢复内置'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(prefs.getString(topicSummaryPromptKey), '内置总结要求');
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('窄屏大字使用正文滚动且卡片不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester, textScale: 2, privateMessage: true);
    await _expand(tester);
    expect(find.byType(ListView), findsNothing);
    expect(find.textContaining('私信内容会发送'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('ai-summary-refresh')),
      150,
      scrollable: scrollable,
    );
    expect(
      find.byKey(const ValueKey('ai-summary-refresh')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('点击即在当前页加载，折叠和待完成重入不重复请求', (tester) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    final pending = Completer<String>();
    var calls = 0;
    await _pump(
      tester,
      visible: visible,
      service: _service(() {
        calls++;
        return pending.future;
      }),
    );
    await _expand(tester);
    expect(calls, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await _expand(tester);
    expect(find.byType(AiTopicSummaryCard), findsNothing);
    await _expand(tester);
    expect(calls, 1);
    visible.value = false;
    await tester.pump();
    visible.value = true;
    await tester.pump();
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(calls, 1);
    pending.complete('**后台完成**');
    await tester.pumpAndSettle();
    expect(
      tester.widget<MarkdownBody>(find.byType(MarkdownBody)).data,
      '**后台完成**',
    );
    expect(find.byType(RelativeTimeText), findsOneWidget);
    expect(find.text('刷新'), findsOneWidget);
    expect(calls, 1);
    await _unmount(tester);
  });

  testWidgets('离页期间完成，返回恢复缓存且继续携带原摘要', (tester) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    final pending = Completer<String>();
    var calls = 0;
    String? continued;
    await _pump(
      tester,
      visible: visible,
      onContinue: (value) => continued = value,
      service: _service(() {
        calls++;
        return pending.future;
      }),
    );
    await _expand(tester);
    visible.value = false;
    await tester.pump();
    pending.complete('1. **结论**\n\n- 后台摘要');
    await tester.pump();
    visible.value = true;
    await tester.pumpAndSettle();
    final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(markdown.data, '1. **结论**\n\n- 后台摘要');
    expect(find.text(markdown.data), findsNothing);
    expect(calls, 1);
    await tester.tap(find.byKey(const ValueKey('ai-summary-continue')));
    expect(continued, markdown.data);
    expect(find.byType(BottomSheet), findsNothing);
    await _unmount(tester);
  });

  testWidgets('内联错误可重试，刷新才重新调用模型', (tester) async {
    var calls = 0;
    await _pump(
      tester,
      service: _service(() async {
        calls++;
        if (calls == 1) throw const TopicSummaryException('测试错误');
        return '第 $calls 次摘要';
      }),
    );
    await _expand(tester);
    await tester.pumpAndSettle();
    expect(find.text('测试错误'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(
      tester.widget<MarkdownBody>(find.byType(MarkdownBody)).data,
      '第 2 次摘要',
    );
    await _expand(tester);
    await _expand(tester);
    expect(calls, 2);
    await tester.tap(find.text('刷新'));
    await tester.pumpAndSettle();
    expect(calls, 3);
    await _unmount(tester);
  });

  testWidgets('取消终止等待，迟到结果不显示', (tester) async {
    final pending = Completer<String>();
    await _pump(tester, service: _service(() => pending.future));
    await _expand(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('已取消总结'), findsOneWidget);
    pending.complete('迟到的结果');
    await tester.pump();
    expect(find.byType(MarkdownBody), findsNothing);
    await _unmount(tester);
  });

  testWidgets('私信账号变化立即折叠、旧任务取消且不落盘', (tester) async {
    final pending = Completer<String>();
    var calls = 0;
    final prefs = await _pump(
      tester,
      privateMessage: true,
      service: _service(() {
        calls++;
        return pending.future;
      }),
    );
    await _expand(tester);
    expect(find.textContaining('私信内容会发送'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AiTopicSummaryButton)),
    );
    container.read(_account.notifier).state = 'site:guest';
    await tester.pump();
    expect(find.byType(AiTopicSummaryCard), findsNothing);
    pending.complete('私密内容');
    await tester.pump();
    await _expand(tester);
    expect(find.text('请先登录后再总结私信。'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsNothing);
    expect(calls, 1);
    expect(
      prefs.getKeys().where((key) => key.contains('ai_topic_summary_v1')),
      isEmpty,
    );
    await _unmount(tester);
  });
  testWidgets('手机摘要页脚继续与刷新同行，大字结果卡片可换行', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(
      tester,
      onContinue: (_) {},
      service: _service(() async => '**主要结论**'),
    );
    await _expand(tester);
    await tester.pumpAndSettle();
    final continuation = find.byKey(const ValueKey('ai-summary-continue'));
    final refresh = find.byKey(const ValueKey('ai-summary-refresh'));
    expect(tester.getCenter(continuation).dy, tester.getCenter(refresh).dy);
    expect(
      tester.getCenter(continuation).dx,
      lessThan(tester.getCenter(refresh).dx),
    );
    expect(tester.takeException(), isNull);
    await _unmount(tester);
    tester.view.physicalSize = const Size(320, 480);
    await _pump(
      tester,
      textScale: 2,
      onContinue: (_) {},
      service: _service(() async => '## 结论\n\n- **重要内容**\n- 后续讨论'),
    );
    await _expand(tester);
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownBody), findsOneWidget);
    await tester.scrollUntilVisible(
      refresh,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(refresh.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });
}
