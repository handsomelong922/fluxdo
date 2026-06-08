import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/widgets/layout/adaptive_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('topDestinationCount keeps only the top group above shortcuts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(220, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 700,
            child: AdaptiveNavigationRail(
              selectedIndex: -1,
              onDestinationSelected: (_) {},
              extended: true,
              topDestinationCount: 1,
              categoryShortcuts: const SizedBox(
                key: ValueKey('shortcuts'),
                height: 80,
              ),
              destinations: const [
                AdaptiveDestination(
                  id: 'home',
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                AdaptiveDestination(
                  id: 'profile',
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
                AdaptiveDestination(
                  id: 'bookmarks',
                  icon: Icon(Icons.bookmark_outline),
                  selectedIcon: Icon(Icons.bookmark),
                  label: 'Bookmarks',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final homeTop = tester.getTopLeft(find.text('Home')).dy;
    final shortcutsTop = tester
        .getTopLeft(find.byKey(const ValueKey('shortcuts')))
        .dy;
    final profileTop = tester.getTopLeft(find.text('Profile')).dy;

    expect(homeTop, lessThan(shortcutsTop));
    expect(shortcutsTop, lessThan(profileTop));
  });

  testWidgets('bottom navigation hides labels and scales selected icon', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AdaptiveBottomNavigation(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              destinations: const [
                AdaptiveDestination(
                  id: 'home',
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(
                    Icons.home,
                    key: ValueKey('selected-home'),
                  ),
                  label: 'Home',
                ),
                AdaptiveDestination(
                  id: 'profile',
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final theme = tester.widget<NavigationBarTheme>(
      find.byType(NavigationBarTheme),
    );
    expect(theme.data.height, 52);
    expect(
      theme.data.labelBehavior,
      NavigationDestinationLabelBehavior.alwaysHide,
    );

    final selectedIconFinder = find.byKey(const ValueKey('selected-home'));
    expect(selectedIconFinder, findsOneWidget);
    final scaledTransform = tester
        .widgetList<Transform>(
          find.ancestor(
            of: selectedIconFinder,
            matching: find.byType(Transform),
          ),
        )
        .any((transform) => transform.transform.getMaxScaleOnAxis() > 1.1);
    expect(scaledTransform, isTrue);
  });
}
