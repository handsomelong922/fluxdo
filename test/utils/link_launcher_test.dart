import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/preferences_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/utils/link_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isInternalUrlString', () {
    test('accepts linux.do topic links with malformed referral spacing', () {
      expect(
        isInternalUrlString('https://linux.do/t/topic/2293666?u = bbrother'),
        isTrue,
      );
    });

    test('accepts nested and canonical linux.do topic links', () {
      expect(
        isInternalUrlString('https://linux.do/n/topic/388420?sort=old'),
        isTrue,
      );
      expect(isInternalUrlString('https://linux.do/topic/388420'), isTrue);
    });

    test('treats encoded external and userscript links as external', () {
      expect(
        isInternalUrlString('https://sub.100xlabs.space/%EF%BC%89'),
        isFalse,
      );
      expect(
        isInternalUrlString('https://greasyfork.org/zh-CN/scripts/123-test'),
        isFalse,
      );
    });
  });

  group('isCdkUrlString', () {
    test('recognizes cdk.linux.do http variants', () {
      expect(isCdkUrlString('https://cdk.linux.do'), isTrue);
      expect(isCdkUrlString('https://cdk.linux.do/abc?code=1'), isTrue);
      expect(isCdkUrlString('//cdk.linux.do/redeem'), isTrue);
    });

    test('does not match other hosts', () {
      expect(isCdkUrlString('https://linux.do/t/1'), isFalse);
      expect(isCdkUrlString('https://example.com/cdk.linux.do'), isFalse);
      expect(isCdkUrlString('/t/1'), isFalse);
    });
  });

  group('launchContentLink', () {
    testWidgets('passes nested route intent for complex topic links', (
      tester,
    ) async {
      var capturedTopicId = 0;
      bool? capturedNestedView;

      void callback(
        int topicId,
        String? topicSlug,
        int? postNumber, {
        bool? initialNestedView,
      }) {
        capturedTopicId = topicId;
        capturedNestedView = initialNestedView;
      }

      late BuildContext testContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              testContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await launchContentLink(
        testContext,
        'https://linux.do/n/topic/388420?sort=old',
        onInternalLinkTap: callback,
      );

      expect(capturedTopicId, 388420);
      expect(capturedNestedView, isTrue);
    });
  });

  group('AppPreferences external link confirmation', () {
    test(
      'defaults to showing confirmation and persists the direct-open switch',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final notifier = PreferencesNotifier(prefs);

        expect(notifier.state.skipExternalLinkConfirmation, isFalse);

        await notifier.setSkipExternalLinkConfirmation(true);
        expect(notifier.state.skipExternalLinkConfirmation, isTrue);
        expect(
          PreferencesNotifier(prefs).state.skipExternalLinkConfirmation,
          isTrue,
        );

        await notifier.setSkipExternalLinkConfirmation(false);
        expect(notifier.state.skipExternalLinkConfirmation, isFalse);
        expect(
          PreferencesNotifier(prefs).state.skipExternalLinkConfirmation,
          isFalse,
        );
      },
    );
  });

  group('launchExternalLink', () {
    testWidgets('launches external URL even when canLaunchUrl is false', (
      tester,
    ) async {
      final previousLauncher = UrlLauncherPlatform.instance;
      final launcher = _FakeUrlLauncher(
        canLaunchResponse: false,
        launchResponse: true,
      );
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);

      SharedPreferences.setMockInitialValues({
        'pref_skip_external_link_confirmation': true,
      });
      final prefs = await SharedPreferences.getInstance();

      late BuildContext testContext;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                testContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      await launchExternalLink(
        testContext,
        'https://sub.100xlabs.space/%EF%BC%89',
      );
      await launchExternalLink(
        testContext,
        'https://greasyfork.org/zh-CN/scripts/123-test',
      );

      expect(launcher.canLaunchCalls, isEmpty);
      expect(launcher.launchCalls, [
        'https://sub.100xlabs.space/%EF%BC%89',
        'https://greasyfork.org/zh-CN/scripts/123-test',
      ]);
    });
  });
}

class _FakeUrlLauncher extends UrlLauncherPlatform {
  _FakeUrlLauncher({
    required this.canLaunchResponse,
    required this.launchResponse,
  });

  final bool canLaunchResponse;
  final bool launchResponse;
  final List<String> canLaunchCalls = [];
  final List<String> launchCalls = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async {
    canLaunchCalls.add(url);
    return canLaunchResponse;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchCalls.add(url);
    return launchResponse;
  }
}
