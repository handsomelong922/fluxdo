import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/ai_post_review_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiPostReviewService', () {
    late SharedPreferences prefs;
    late String? capturedSystemPrompt;
    late List<Map<String, String>>? capturedMessages;

    const provider = AiProvider(
      id: 'provider-1',
      name: 'Provider',
      type: AiProviderType.openai,
      baseUrl: 'https://example.com/v1',
      models: [AiModel(id: 'text-model')],
    );
    const model = AiModel(id: 'text-model');

    Future<AiPostReviewResult> reviewWith({
      required Future<String> Function() guidelinesFetcher,
      String? apiKey = 'secret',
      String response = '{"level":"medium","suggestions":["把攻击性表达改成更中性的描述"]}',
    }) async {
      final service = AiPostReviewService(
        prefs: prefs,
        chatService: _FakeAiChatService(
          onSend: ({required systemPrompt, required messages}) {
            capturedSystemPrompt = systemPrompt;
            capturedMessages = messages;
            return Stream<String>.value(response);
          },
        ),
        apiKeyLoader: (_) async => apiKey,
        guidelinesFetcher: guidelinesFetcher,
      );

      return service.review(
        const AiPostReviewRequest(
          provider: provider,
          model: model,
          title: '测试标题',
          content: '这是一段需要审核的正文内容。',
          target: AiPostReviewTarget.topic,
          categoryName: '开发调优',
          categoryDescription: '讨论开发、性能调优和工程实践。',
          tags: ['linux', 'flutter'],
        ),
      );
    }

    setUp(() async {
      capturedSystemPrompt = null;
      capturedMessages = null;
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('在线获取社区准则成功后写入缓存', () async {
      final guidelines = _guidelinesHtml('请保持友善，避免人身攻击。');

      final result = await reviewWith(
        guidelinesFetcher: () async => guidelines,
      );

      expect(result.usedCachedGuidelines, isFalse);
      expect(
        prefs.getString(AiPostReviewService.guidelinesCacheKey),
        contains('请保持友善'),
      );
      expect(capturedSystemPrompt, contains('不得提供完整改写内容'));
      expect(capturedSystemPrompt, contains('只能给方向'));
      expect(capturedSystemPrompt, contains('1-3 条建议'));
      expect(capturedMessages?.single['content'], contains('开发调优'));
      expect(capturedMessages?.single['content'], contains('讨论开发、性能调优和工程实践。'));
      expect(capturedMessages?.single['content'], contains('linux、flutter'));
    });

    test('在线获取失败时使用上次缓存的社区准则', () async {
      await prefs.setString(
        AiPostReviewService.guidelinesCacheKey,
        '上次缓存的社区准则：请文明交流。',
      );

      final result = await reviewWith(
        guidelinesFetcher: () async => throw StateError('network failed'),
      );

      expect(result.usedCachedGuidelines, isTrue);
      expect(capturedSystemPrompt, contains('上次缓存的社区准则'));
    });

    test('在线获取失败且无缓存时抛出可复制详情的错误', () async {
      expect(
        () => reviewWith(
          guidelinesFetcher: () async => throw StateError('network failed'),
        ),
        throwsA(isA<AiPostReviewException>()),
      );
    });

    test('提示词明确禁止完整改写', () {
      final prompt = AiPostReviewService.buildSystemPrompt('社区准则');

      expect(prompt, contains('不得提供完整改写内容'));
      expect(prompt, contains('不得输出可直接复制发布的完整帖子'));
      expect(prompt, contains('只能给方向'));
      expect(prompt, contains('1-3 条建议'));
      expect(prompt, contains('"level"'));
    });

    test('疑似完整改写的建议会被隐藏', () {
      final longRewrite = List.filled(30, '这是可以直接复制发布的完整改写内容').join();
      final result = AiPostReviewService.parseResult(
        '{"level":"high","suggestions":["$longRewrite"]}',
        usedCachedGuidelines: false,
      );

      expect(result.level, AiPostReviewLevel.high);
      expect(result.suggestions.single, contains('疑似完整改写内容'));
      expect(result.suggestions.single, isNot(contains('可以直接复制发布')));
    });

    test('只保留前三条建议', () {
      final result = AiPostReviewService.parseResult(
        '{"level":"low","suggestions":["一","二","三","四"]}',
        usedCachedGuidelines: false,
      );

      expect(result.level, AiPostReviewLevel.low);
      expect(result.suggestions, ['一', '二', '三']);
    });

    test('非法等级默认按中等级展示', () {
      final result = AiPostReviewService.parseResult(
        '{"level":"unknown","suggestions":["检查分区是否准确"]}',
        usedCachedGuidelines: false,
      );

      expect(result.level, AiPostReviewLevel.medium);
      expect(result.suggestions.single, '检查分区是否准确');
    });

    test('异常页不会被当成社区准则写入缓存', () async {
      await expectLater(
        reviewWith(
          guidelinesFetcher: () async =>
              '<html><body>Cloudflare checking your browser. Enable JavaScript to continue.</body></html>',
        ),
        throwsA(isA<AiPostReviewException>()),
      );

      expect(prefs.getString(AiPostReviewService.guidelinesCacheKey), isNull);
    });
  });
}

String _guidelinesHtml(String text) {
  final body = List.filled(20, text).join('\n');
  return '<html><body><main>$body</main></body></html>';
}

typedef _FakeSend =
    Stream<String> Function({
      required String? systemPrompt,
      required List<Map<String, String>> messages,
    });

class _FakeAiChatService extends AiChatService {
  _FakeAiChatService({required _FakeSend onSend}) : _onSend = onSend;

  final _FakeSend _onSend;

  @override
  Stream<String> sendChatStream({
    required AiProvider provider,
    required String model,
    required String apiKey,
    required List<Map<String, String>> messages,
    String? systemPrompt,
    ThinkingConfig thinkingConfig = const ThinkingConfig(),
    AiModelFeatureConfig featureConfig = const AiModelFeatureConfig(),
  }) {
    return _onSend(systemPrompt: systemPrompt, messages: messages);
  }
}
