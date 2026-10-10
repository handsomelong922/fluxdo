import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/preferences_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('正则独立持久化，旧关键词和完整词偏好保持不变', () async {
    SharedPreferences.setMockInitialValues({
      'pref_topic_filter_keywords': ['a.b', '(旧词)'],
      'pref_topic_filter_whole_word': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    expect(
      container.read(preferencesProvider).topicFilterRegexPatterns,
      isEmpty,
    );
    await container
        .read(preferencesProvider.notifier)
        .setTopicFilterRegexPatterns([' (手机|电脑).*AI ', '(手机|电脑).*AI']);
    final reloaded = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(reloaded.dispose);
    final state = reloaded.read(preferencesProvider);
    expect(state.topicFilterRegexPatterns, [' (手机|电脑).*AI ', '(手机|电脑).*AI']);
    expect(state.topicFilterKeywords, ['a.b', '(旧词)']);
    expect(state.topicFilterWholeWord, isTrue);
  });

  test('非法正则保存失败，内存和磁盘都保留原值', () async {
    SharedPreferences.setMockInitialValues({
      'pref_topic_filter_regex_patterns': [r'^AI$'],
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    await expectLater(
      container.read(preferencesProvider.notifier).setTopicFilterRegexPatterns([
        '(',
      ]),
      throwsFormatException,
    );
    expect(container.read(preferencesProvider).topicFilterRegexPatterns, [
      r'^AI$',
    ]);
    expect(prefs.getStringList('pref_topic_filter_regex_patterns'), [r'^AI$']);
  });

  test('用户名批量输入正规化后保存且重新加载一致', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    await container.read(preferencesProvider.notifier).setBlockedUsernames([
      '@Alice，bob @ALICE\ncarol, @Dave',
    ]);
    expect(prefs.getStringList('pref_blocked_usernames'), [
      'Alice',
      'bob',
      'carol',
      'Dave',
    ]);
    expect(container.read(preferencesProvider).normalizedBlockedUsernames, {
      'alice',
      'bob',
      'carol',
      'dave',
    });
  });
}
