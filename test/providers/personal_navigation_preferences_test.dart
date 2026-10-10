import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluxdo/providers/personal_navigation_preferences_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';

void main() {
  test('默认保持滑动且关闭右区；未知存储值安全回退', () async {
    SharedPreferences.setMockInitialValues({'pref_page_transition_style': 'unknown'});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    final value = container.read(personalNavigationPreferencesProvider);
    expect(value.pageTransitionStyle, PageTransitionStyle.cupertino);
    expect(value.rightEdgeTapPreview, isFalse);
  });

  test('两个偏好独立持久化且不改已有长按设置', () async {
    SharedPreferences.setMockInitialValues({'pref_long_press_preview': false});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer create() => ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    final container = create();
    final notifier = container.read(personalNavigationPreferencesProvider.notifier);
    await notifier.setRightEdgeTapPreview(true);
    await notifier.setPageTransitionStyle(PageTransitionStyle.scale);
    expect(container.read(personalNavigationPreferencesProvider).rightEdgeTapPreview, isTrue);
    container.dispose();
    final restored = create();
    addTearDown(restored.dispose);
    expect(restored.read(personalNavigationPreferencesProvider).rightEdgeTapPreview, isTrue);
    expect(restored.read(personalNavigationPreferencesProvider).pageTransitionStyle, PageTransitionStyle.scale);
    expect(prefs.getBool('pref_long_press_preview'), isFalse);
  });
}
