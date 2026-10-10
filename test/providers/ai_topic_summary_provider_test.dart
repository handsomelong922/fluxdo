import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/ai_topic_summary_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/ai_topic_summary_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('真实缓存键按账号、站点、话题、服务地址、模型和 Prompt 隔离', () {
    String key({String account = 'site:1', int topic = 1, String url = 'https://example.invalid',
      String model = 'model', String prompt = 'prompt', bool private = false}) => topicSummaryTaskKey(
      account: account, topicId: topic,
      provider: AiProvider(id: 'provider', name: 'Provider', type: AiProviderType.openai, baseUrl: url),
      model: AiModel(id: model), prompt: prompt, isPrivateMessage: private);
    expect({key(), key(account: 'site:2'), key(account: 'other-site:1'), key(topic: 2),
      key(url: 'https://other.invalid'), key(model: 'other'), key(prompt: 'other'), key(private: true)}.length, 8);
    expect(key(prompt: ' prompt '), key());
    expect(key(), isNot(contains('prompt')));
  });

  test('换账号销毁旧 owner；普通总结落盘，私信只在当前账号内存保留', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      aiTopicSummaryAccountProvider.overrideWithValue('site:1'),
    ]);
    addTearDown(container.dispose);
    final owner = container.read(aiTopicSummaryTasksProvider);
    AiTopicSummaryService service() => AiTopicSummaryService(
      loadTopic: () async => const SummarySnapshot('title', [1], [SummaryPost(1, 1, 'a', 'body')]),
      loadPosts: (_) async => [], generate: (_, _, _) async => 'summary');
    await owner.start('public_key', prompt: 'p', createService: () async => service());
    await owner.start('private_key', prompt: 'p', createService: () async => service());
    expect(prefs.getString('public_key'), isNotNull);
    expect(prefs.getString('private_key'), isNull);
    expect(owner.state('private_key').result!.text, 'summary');
    container.updateOverrides([
      sharedPreferencesProvider.overrideWithValue(prefs),
      aiTopicSummaryAccountProvider.overrideWithValue('site:2'),
    ]);
    await container.pump();
    final next = container.read(aiTopicSummaryTasksProvider);
    expect(identical(owner, next), isFalse);
    expect(owner.state('private_key').result, isNull);
    expect(next.state('private_key').result, isNull);
  });
  test('持久化缓存最多保留 100 个最新总结', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      aiTopicSummaryAccountProvider.overrideWithValue('site:1'),
    ]);
    addTearDown(container.dispose);
    final owner = container.read(aiTopicSummaryTasksProvider);
    for (var i = 0; i < 105; i++) {
      await owner.start('ai_topic_summary_v1_$i', prompt: 'p', createService: () async => AiTopicSummaryService(
        loadTopic: () async => const SummarySnapshot('title', [1], [SummaryPost(1, 1, 'a', 'body')]),
        loadPosts: (_) async => [], generate: (_, _, _) async => 'summary $i'));
    }
    expect(prefs.getKeys().where((k) => k.startsWith('ai_topic_summary_v1_')).length, 100);
    expect(prefs.getString('ai_topic_summary_v1_104'), isNotNull);
  });

}
