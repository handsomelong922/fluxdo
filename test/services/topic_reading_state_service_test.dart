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
      await service.flushPendingWrites();

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
      await service.flushPendingWrites();

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

    test(
      'debounces repeated writes and keeps latest visible immediately',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final service = TopicReadingStateService(
          prefs,
          saveDebounce: const Duration(milliseconds: 50),
        );

        await service.saveState(topicId: 42, postNumber: 10, nestedView: false);
        await service.saveState(topicId: 42, postNumber: 20, nestedView: true);

        final immediate = service.getState(42);
        expect(immediate, isNotNull);
        expect(immediate!.postNumber, 20);
        expect(immediate.nestedView, isTrue);

        expect(prefs.getString('topic_reading_state_42'), isNull);

        await Future<void>.delayed(const Duration(milliseconds: 80));

        final persisted = service.getState(42);
        expect(persisted, isNotNull);
        expect(persisted!.postNumber, 20);
        expect(persisted.nestedView, isTrue);
      },
    );

    test('skips redundant saves for unchanged reading position', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = TopicReadingStateService(
        prefs,
        saveDebounce: const Duration(milliseconds: 50),
      );

      await service.saveState(topicId: 42, postNumber: 20, nestedView: true);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final firstPersisted = prefs.getString('topic_reading_state_42');
      expect(firstPersisted, isNotNull);

      await service.saveState(topicId: 42, postNumber: 20, nestedView: true);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(prefs.getString('topic_reading_state_42'), firstPersisted);
    });
  });
}
