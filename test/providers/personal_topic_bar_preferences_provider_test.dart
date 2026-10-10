import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/personal_topic_bar_preferences_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认四按钮顺序固定，修改后新容器恢复顺序', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    expect(
      first.read(personalTopicBarPreferencesProvider),
      TopicBarAction.values,
    );
    final order = TopicBarAction.values.reversed.toList();
    await first
        .read(personalTopicBarPreferencesProvider.notifier)
        .setOrder(order);
    first.dispose();
    final second = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(second.dispose);
    expect(second.read(personalTopicBarPreferencesProvider), order);
    await second.read(personalTopicBarPreferencesProvider.notifier).reset();
    expect(
      prefs.getStringList(topicBarOrderPreferenceKey),
      TopicBarAction.values.map((action) => action.name).toList(),
    );
  });

  test('旧数据的未知或重复项被移除，缺失按钮按默认次序补回', () async {
    SharedPreferences.setMockInitialValues({
      topicBarOrderPreferenceKey: ['bookmark', 'unknown', 'bookmark', 'share'],
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    expect(container.read(personalTopicBarPreferencesProvider), [
      TopicBarAction.bookmark,
      TopicBarAction.share,
      TopicBarAction.scrollToTop,
      TopicBarAction.filter,
    ]);
  });
}
