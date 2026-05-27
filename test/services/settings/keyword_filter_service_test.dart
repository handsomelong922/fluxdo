import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/settings/keyword_filter_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('KeywordFilterNotifier', () {
    test('matches compiled regex rules case-insensitively', () async {
      SharedPreferences.setMockInitialValues({
        'custom_keyword_filter_patterns': ['福利|抽奖'],
      });
      final prefs = await SharedPreferences.getInstance();
      final notifier = KeywordFilterNotifier(prefs);

      expect(notifier.matches('今天有福利'), isTrue);
      expect(notifier.matches('普通话题'), isFalse);
    });

    test('rebuilds compiled rules after edits and removals', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = KeywordFilterNotifier(prefs);

      expect(notifier.add('foo'), isTrue);
      expect(notifier.matches('FOO'), isTrue);

      expect(notifier.editAt(0, 'bar'), isTrue);
      expect(notifier.matches('FOO'), isFalse);
      expect(notifier.matches('bar'), isTrue);

      notifier.remove('bar');
      expect(notifier.matches('bar'), isFalse);
    });
  });
}
