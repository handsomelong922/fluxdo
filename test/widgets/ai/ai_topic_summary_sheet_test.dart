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

  Future<SharedPreferences> pumpSheet(WidgetTester tester, {AiTopicSummaryService? service}) async {
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
      aiTopicSummaryApiKeyLoaderProvider.overrideWithValue((_) async => 'mock-key'),
      if (service != null) aiTopicSummaryServiceFactoryProvider.overrideWithValue(
        ({required topicId, required provider, required model, required apiKey}) => service),
      aiTopicSummaryDefaultPromptProvider.overrideWithValue('内置总结要求'),
    ], child: TranslationProvider(child: MaterialApp(
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      supportedLocales: AppLocaleUtils.supportedLocales,
      home: const Scaffold(body: AiTopicSummarySheet(topicId: 1, isPrivateMessage: true)),
    ))));
    await tester.pumpAndSettle();
    return prefs;
  }

  testWidgets('未配置模型时禁止发送并提供已有模型设置入口', (tester) async {
    await pumpSheet(tester);
    expect(find.text('尚未配置文本模型'), findsOneWidget);
    expect(find.textContaining('这是私信'), findsOneWidget);
    final start = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '读取并准备总结'));
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
    await pumpSheet(tester);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('读取并准备总结'), 150);
    expect(find.text('读取并准备总结'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
  testWidgets('读取后需确认才发AI，重复点击不重复启动，取消终止等待', (tester) async {
    var reads = 0;
    var calls = 0;
    final pending = Completer<String>();
    final service = AiTopicSummaryService(
      loadTopic: () async { reads++; return const SummarySnapshot('标题', [1], [SummaryPost(1, 1, '用户', '主帖')]); },
      loadPosts: (_) async => [], generate: (_, _, _) { calls++; return pending.future; },
    );
    await pumpSheet(tester, service: service);
    await tester.tap(find.text('读取并准备总结'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('确认发送给 AI'), findsOneWidget);
    expect(find.textContaining('本次预计 1 次 AI 请求'), findsOneWidget);
    expect(calls, 0);
    expect(reads, 1);
    await tester.tap(find.text('发送并总结'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 1);
    final start = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '读取并准备总结'));
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

}
