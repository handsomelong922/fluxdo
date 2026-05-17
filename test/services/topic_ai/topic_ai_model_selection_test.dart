import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/topic_ai/topic_ai_model_selection.dart';

void main() {
  group('hasConfiguredTopicAiModel', () {
    const provider = AiProvider(
      id: 'provider-1',
      name: 'Provider 1',
      type: AiProviderType.openai,
      baseUrl: 'https://api.example.com/v1',
      models: [AiModel(id: 'model-1', name: 'Model 1')],
    );
    const selection = (provider: provider, model: AiModel(id: 'model-1'));

    test('returns false when no model is selected', () async {
      final configured = await hasConfiguredTopicAiModel(
        null,
        readApiKey: (_) async => 'secret',
      );

      expect(configured, isFalse);
    });

    test('returns false when api key is missing', () async {
      final configured = await hasConfiguredTopicAiModel(
        selection,
        readApiKey: (_) async => null,
      );

      expect(configured, isFalse);
    });

    test('returns false when api key is blank', () async {
      final configured = await hasConfiguredTopicAiModel(
        selection,
        readApiKey: (_) async => '   ',
      );

      expect(configured, isFalse);
    });

    test('returns true when model and api key are both available', () async {
      final configured = await hasConfiguredTopicAiModel(
        selection,
        readApiKey: (_) async => 'secret',
      );

      expect(configured, isTrue);
    });
  });
}
