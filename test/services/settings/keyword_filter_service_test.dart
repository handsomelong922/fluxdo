import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/settings/keyword_filter_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('KeywordFilterNotifier.replaceAllPatterns', () {
    test('persists normalized valid patterns', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = KeywordFilterNotifier(prefs);

      final ok = notifier.replaceAllPatterns(['  广告  ', '推广|营销']);

      expect(ok, isTrue);
      expect(notifier.state, ['广告', '推广|营销']);
      expect(prefs.getStringList('custom_keyword_filter_patterns'), [
        '广告',
        '推广|营销',
      ]);
    });

    test(
      'rejects invalid or duplicated patterns without changing state',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final notifier = KeywordFilterNotifier(prefs);
        notifier.replaceAllPatterns(['广告']);

        expect(notifier.replaceAllPatterns(['广告', '广告']), isFalse);
        expect(notifier.state, ['广告']);

        expect(notifier.replaceAllPatterns(['[']), isFalse);
        expect(notifier.state, ['广告']);
      },
    );

    test('matches caches titles and clears cache when patterns change', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = KeywordFilterNotifier(prefs);

      expect(notifier.replaceAllPatterns(['广告']), isTrue);

      expect(notifier.matches('广告位招租'), isTrue);
      expect(notifier.matches('普通帖子'), isFalse);
      expect(notifier.debugMatchCacheSize, 2);

      expect(notifier.replaceAllPatterns(['普通']), isTrue);
      expect(notifier.debugMatchCacheSize, 0);
      expect(notifier.matches('普通帖子'), isTrue);
    });
  });
}
