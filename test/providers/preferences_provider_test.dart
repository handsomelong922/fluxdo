import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PreferencesNotifier auto summary settings', () {
    test('uses safe defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = PreferencesNotifier(prefs);

      expect(notifier.state.autoSummarizeTopicOnEnter, isFalse);
      expect(notifier.state.autoSummarizeMinReplies, 20);
    });

    test('persists switch and clamps minimum replies', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = PreferencesNotifier(prefs);

      await notifier.setAutoSummarizeTopicOnEnter(true);
      await notifier.setAutoSummarizeMinReplies(500);

      expect(notifier.state.autoSummarizeTopicOnEnter, isTrue);
      expect(notifier.state.autoSummarizeMinReplies, 200);
      expect(prefs.getBool('pref_auto_summarize_topic_on_enter'), isTrue);
      expect(prefs.getInt('pref_auto_summarize_min_replies'), 200);
    });
  });
}
