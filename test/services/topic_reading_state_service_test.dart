import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/topic_reading_state_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('TopicReadingStateService', () {
    test('saves and loads topic reading state', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = TopicReadingStateService(prefs);

      await service.saveState(topicId: 42, postNumber: 128, nestedView: true);

      final state = service.getState(42);

      expect(state, isNotNull);
      expect(state!.topicId, 42);
      expect(state.postNumber, 128);
      expect(state.nestedView, isTrue);
    });

    test('does not save invalid post numbers', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = TopicReadingStateService(prefs);

      await service.saveState(topicId: 42, postNumber: 0, nestedView: false);

      expect(service.getState(42), isNull);
    });

    test('ignores malformed entries', () async {
      SharedPreferences.setMockInitialValues({
        'topic_reading_state_42': '{not-json',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = TopicReadingStateService(prefs);

      expect(service.getState(42), isNull);
    });
  });
}
