import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiProvider API Key storage', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('reads trimmed plaintext API key from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'ai_apikey_provider-1': '  sk  ',
      });

      final apiKey = await AiProviderListNotifier.getApiKey('provider-1');

      expect(apiKey, 'sk');
    });

    test('addProvider stores trimmed API key in plaintext prefs', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = AiProviderListNotifier(prefs);

      final id = await notifier.addProvider(
        name: 'Provider',
        type: AiProviderType.openai,
        baseUrl: 'https://example.com/v1',
        apiKey: '  secret  ',
      );

      expect(prefs.getString('ai_apikey_$id'), 'secret');
      expect(await AiProviderListNotifier.getApiKey(id), 'secret');
    });

    test('blank API key update clears stored key', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = AiProviderListNotifier(prefs);
      final id = await notifier.addProvider(
        name: 'Provider',
        type: AiProviderType.openai,
        baseUrl: 'https://example.com/v1',
        apiKey: 'secret',
      );

      await notifier.updateProvider(id: id, apiKey: '   ');

      expect(prefs.getString('ai_apikey_$id'), isNull);
      expect(await AiProviderListNotifier.getApiKey(id), isNull);
    });
  });
}
