import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_provider.dart';

/// 默认保留无整页透明度图层的 Cupertino 转场。
enum PageTransitionStyle {
  cupertino,
  fade,
  scale,
  none;

  static PageTransitionStyle fromString(String? value) => values.firstWhere(
    (style) => style.name == value,
    orElse: () => cupertino,
  );
}

class PersonalNavigationPreferences {
  const PersonalNavigationPreferences({
    this.pageTransitionStyle = PageTransitionStyle.cupertino,
    this.rightEdgeTapPreview = false,
  });

  final PageTransitionStyle pageTransitionStyle;
  final bool rightEdgeTapPreview;
}

class PersonalNavigationPreferencesNotifier
    extends StateNotifier<PersonalNavigationPreferences> {
  PersonalNavigationPreferencesNotifier(this._prefs)
      : super(PersonalNavigationPreferences(
          pageTransitionStyle: PageTransitionStyle.fromString(
            _prefs.getString('pref_page_transition_style'),
          ),
          rightEdgeTapPreview:
              _prefs.getBool('pref_right_edge_tap_preview') ?? false,
        ));

  final SharedPreferences _prefs;

  Future<void> setPageTransitionStyle(PageTransitionStyle value) async {
    state = PersonalNavigationPreferences(
      pageTransitionStyle: value,
      rightEdgeTapPreview: state.rightEdgeTapPreview,
    );
    await _prefs.setString('pref_page_transition_style', value.name);
  }

  Future<void> setRightEdgeTapPreview(bool value) async {
    state = PersonalNavigationPreferences(
      pageTransitionStyle: state.pageTransitionStyle,
      rightEdgeTapPreview: value,
    );
    await _prefs.setBool('pref_right_edge_tap_preview', value);
  }
}

final personalNavigationPreferencesProvider = StateNotifierProvider<
    PersonalNavigationPreferencesNotifier, PersonalNavigationPreferences>(
  (ref) => PersonalNavigationPreferencesNotifier(ref.watch(sharedPreferencesProvider)),
);
