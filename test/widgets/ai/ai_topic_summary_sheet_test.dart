import 'dart:async';
import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/app_localizations.dart';
import 'package:fluxdo/providers/ai_topic_summary_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/widgets/ai/ai_topic_summary_sheet.dart';
import 'package:fluxdo/services/ai_topic_summary_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {

  Future<SharedPreferences> pumpSheet(WidgetTester tester, {AiTopicSummaryService? service, double textScale = 1}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      aiSharedPreferencesProvider.overrideWithValue(prefs),
      aiTopicSummaryModelProvider.overrideWithValue(service == null ? null : (
        provider: AiProvider(id: 'mock', name: 'Mock AI', type: AiProviderType.openai,
          baseUrl: 'https://example.invalid', models: const [AiModel(id: 'mock-model')]),
        model: const AiModel(id: 'mock-model'),
      )),
      aiTopicSummaryAccountProvider.overrideWithValue('https://example.invalid:42'),
      aiTopicSummaryApiKeyLoaderProvider.overrideWithValue((_) async => 'mock-key'),
      if (service != null) aiTopicSummaryServiceFactoryProvider.overrideWithValue(
        ({required topicId, required provider, required model, required apiKey}) => service),
      aiTopicSummaryDefaultPromptProvider.overrideWithValue('内置总结要求'),
    ], child: TranslationProvider(child: MaterialApp(
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      supportedLocales: AppLocaleUtils.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const Scaffold(body: AiTopicSummarySheet(topicId: 1, isPrivateMessage: true)),
    ))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return prefs;
  }

  testWidgets('未配置模型时禁止发送并提供已有模型设置入口', (tester) async {
    await pumpSheet(tester);
    expect(find.text('尚未配置文本模型'), findsOneWidget);
    expect(find.textContaining('这是私信'), findsOneWidget);
    final start = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '开始总结'));
    expect(start.onPressed, isNull);
    await tester.tap(find.text('模型设置'));
    await tester.pumpAndSettle();
    expect(find.byType(AiProvidersPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('Prompt 保存后再次打开保留，恢复内置可明确保存', (tester) async {
    final prefs = await pumpSheet(tester);
    await tester.tap(find.text('总结 Prompt'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '重点总结技术争议和楼层');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(prefs.getString(topicSummaryPromptKey), '重点总结技术争议和楼层');
    await tester.tap(find.text('总结 Prompt'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '重点总结技术争议和楼层');
    await tester.tap(find.text('恢复内置'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(prefs.getString(topicSummaryPromptKey), '内置总结要求');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('窄屏横向与大字布局不溢出', (tester) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpSheet(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    final sheet = find.byType(AiTopicSummarySheet);
    expect(MediaQuery.textScalerOf(tester.element(sheet)).scale(16), 32);
    final list = find.descendant(of: sheet, matching: find.byType(ListView));
    expect(list, findsOneWidget);
    // ListView 的第一个 Scrollable 是外层视口；正文 SelectableText
    // 自带的内部 Scrollable 不能作为整张面板的滚动目标。
    final scrollable = find.descendant(of: list, matching: find.byType(Scrollable)).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    final initialOffset = position.pixels;
    await tester.drag(scrollable, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(initialOffset));
    await tester.scrollUntilVisible(find.text('开始总结'), 150, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(initialOffset));
    expect(find.text('开始总结').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
  testWidgets('打开即后台总结，无二次确认，取消终止等待', (tester) async {
    var reads = 0;
    var calls = 0;
    final pending = Completer<String>();
    final service = AiTopicSummaryService(
      loadTopic: () async { reads++; return const SummarySnapshot('标题', [1], [SummaryPost(1, 1, '用户', '主帖')]); },
      loadPosts: (_) async => [], generate: (_, _, _) { calls++; return pending.future; },
    );
    await pumpSheet(tester, service: service);
    expect(find.text('确认发送给 AI'), findsNothing);
    expect(reads, 1);
    expect(calls, 1);
    final start = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '开始总结'));
    expect(start.onPressed, isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('已取消总结'), findsOneWidget);
    pending.complete('迟到的结果');
    await tester.pump();
    expect(find.text('迟到的结果'), findsNothing);
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('离开面板后继续后台任务，重新打开直接查看结果且不重复请求', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);
    final pending = Completer<String>();
    var calls = 0;
    final model = (provider: AiProvider(id: 'mock', name: 'Mock AI', type: AiProviderType.openai,
      baseUrl: 'https://example.invalid'), model: const AiModel(id: 'mock-model'));
    await tester.pumpWidget(ProviderScope(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      aiSharedPreferencesProvider.overrideWithValue(prefs),
      aiTopicSummaryAccountProvider.overrideWithValue('site:42'),
      aiTopicSummaryModelProvider.overrideWithValue(model),
      aiTopicSummaryDefaultPromptProvider.overrideWithValue('summarize'),
      aiTopicSummaryApiKeyLoaderProvider.overrideWithValue((_) async => 'mock-key'),
      aiTopicSummaryServiceFactoryProvider.overrideWithValue(
        ({required topicId, required provider, required model, required apiKey}) => AiTopicSummaryService(
          loadTopic: () async => const SummarySnapshot('title', [1], [SummaryPost(1, 1, 'a', 'body')]),
          loadPosts: (_) async => [], generate: (_, _, _) { calls++; return pending.future; })),
    ], child: TranslationProvider(child: MaterialApp(home: Scaffold(body:
      ValueListenableBuilder<bool>(valueListenable: visible, builder: (_, show, _) =>
        show ? const AiTopicSummarySheet(topicId: 1) : const Text('another page')))))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, 1);
    visible.value = false;
    await tester.pump();
    pending.complete('后台完成的总结');
    await tester.pump();
    visible.value = true;
    await tester.pumpAndSettle();
    expect(find.text('后台完成的总结'), findsOneWidget);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

}
