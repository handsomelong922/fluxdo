import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/preferences_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container({
  Map<String, Object> values = const {},
}) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('隐藏首页头像默认关闭，copyWith 保留并可恢复原值', () async {
    final container = await _container();
    final original = container.read(preferencesProvider);
    expect(original.hideHomeAvatars, isFalse);
    final hidden = original.copyWith(hideHomeAvatars: true);
    expect(hidden.hideHomeAvatars, isTrue);
    expect(hidden.copyWith(anonymousShare: true).hideHomeAvatars, isTrue);
    expect(hidden.copyWith(hideHomeAvatars: false).hideHomeAvatars, isFalse);
    expect(original.hideHomeAvatars, isFalse);
  });

  test('首页头像开关即时更新，开启与关闭均持久化并在重建后恢复', () async {
    final container = await _container();
    final prefs = container.read(sharedPreferencesProvider);
    for (final enabled in [true, false]) {
      final updating = container
          .read(preferencesProvider.notifier)
          .setHideHomeAvatars(enabled);
      expect(container.read(preferencesProvider).hideHomeAvatars, enabled);
      await updating;
      expect(prefs.getBool('pref_hide_home_avatars'), enabled);
      final reloaded = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(reloaded.dispose);
      expect(reloaded.read(preferencesProvider).hideHomeAvatars, enabled);
    }
  });

  for (final enabled in [true, false]) {
    test('恢复已保存的首页头像开关：$enabled', () async {
      final container = await _container(
        values: {'pref_hide_home_avatars': enabled},
      );
      expect(container.read(preferencesProvider).hideHomeAvatars, enabled);
    });
  }
}
