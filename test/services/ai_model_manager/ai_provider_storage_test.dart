import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiProviderListNotifier API key storage', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('migrates temporary prefs API key back to secure storage', () async {
      SharedPreferences.setMockInitialValues({
        'ai_apikey_provider-1': '  sk-temp  ',
      });

      final key = await AiProviderListNotifier.getApiKey('provider-1');

      expect(key, 'sk-temp');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ai_apikey_provider-1'), isNull);
      expect(
        prefs.getString('__secure_fallback__ai_provider_key_provider-1'),
        'sk-temp',
      );
    });
  });
}
