import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/services/cf_challenge_service.dart';
import 'package:fluxdo/services/local_notification_service.dart'
    show navigatorKey;
import 'package:fluxdo/services/network/cookie/cookie_jar_service.dart';
import 'package:fluxdo/services/network/exceptions/api_exception.dart';
import 'package:fluxdo/widgets/common/error_view.dart';

import '../../support/cf_test_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = CfTestPlatform();
  final cf = CfChallengeService();
  setUpAll(platform.initialize);
  setUp(() async {
    await platform.reset();
    cf.resetCooldown();
  });
  tearDown(platform.reset);

  Future<void> mount(WidgetTester tester, Widget child) async {
    SharedPreferences.setMockInitialValues({'pref_dialog_blur': false});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TranslationProvider(
          child: MaterialApp(
            navigatorKey: navigatorKey,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocaleUtils.supportedLocales,
            home: Scaffold(body: child),
          ),
        ),
      ),
    );
  }

  Future<void> unmount(WidgetTester tester) async {
    // Toast's dismissal timer and reverse animation must finish on a mounted
    // overlay, as must the delayed clearance-refresh restart after readiness.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  }

  Future<void> start(WidgetTester tester) async {
    final button = tester.widget<FilledButton>(find.byType(FilledButton).first);
    button.onPressed!();
    button.onPressed!(); // Same-frame double tap must still join only once.
    for (var i = 0; i < 20 && platform.webView == null; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(platform.webView, isNotNull);
    platform.webView!.params.onWebViewCreated!(platform.controller.wrapped);
    await tester.pump();
  }

  void finish() => platform.webView!.params.onReceivedHttpError!(
    platform.controller.wrapped,
    WebResourceRequest(
      url: WebUri('https://linux.do/challenge'),
      isForMainFrame: true,
    ),
    WebResourceResponse(statusCode: 404),
  );

  testWidgets(
    'manual success retries once after cookie snapshot and teardown',
    (tester) async {
      var retries = 0;
      await mount(
        tester,
        ErrorView(
          error: CfChallengeException(autoVerifyDisabled: true),
          onRetry: () {
            expect(cf.isVerifying, isFalse);
            retries++;
          },
        ),
      );
      final retryBeforeRebuild = tester
          .widget<InkWell>(
            find
                .ancestor(
                  of: find.text(S.current.common_retry),
                  matching: find.byType(InkWell),
                )
                .first,
          )
          .onTap!;
      await start(tester);
      retryBeforeRebuild();
      expect(
        retries,
        0,
        reason: 'a previously captured Retry callback is guarded',
      );
      final snapshot = Completer<Cookie?>();
      platform.cookies.readValue = (_) => snapshot.future;
      platform.cookies.values = [cfTestCookie('verified')];
      finish();
      await tester.pump(const Duration(seconds: 2));
      expect(retries, 0, reason: 'teardown alone cannot release stale cookies');
      snapshot.complete(cfTestCookie('verified'));
      await tester.pump();
      await tester.pump();
      expect(await CookieJarService().getCfClearance(), 'verified');
      expect(retries, 1);
      await tester.pump(const Duration(milliseconds: 400));
      await unmount(tester);
    },
  );

  testWidgets(
    'replacement error is not retried by a late verification callback',
    (tester) async {
      var retries = 0;
      Object error = CfChallengeException(autoVerifyDisabled: true);
      late StateSetter rebuild;
      await mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return ErrorView(error: error, onRetry: () => retries++);
          },
        ),
      );
      await start(tester);
      rebuild(() => error = StateError('newer request failed'));
      finish();
      await tester.pump(const Duration(seconds: 2));
      expect(retries, 0);
      await unmount(tester);
    },
  );

  testWidgets('failed verification never retries', (tester) async {
    var retries = 0;
    await mount(
      tester,
      ErrorView(
        error: CfChallengeException(autoVerifyDisabled: true),
        onRetry: () => retries++,
      ),
    );
    await start(tester);
    tester.widget<CfChallengePage>(find.byType(CfChallengePage)).onResult!(
      false,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(retries, 0);
    await unmount(tester);
  });

  testWidgets(
    'raw CF challenge after a bounded retry offers manual verification',
    (tester) async {
      final options = RequestOptions(path: 'https://linux.do/latest.json');
      await mount(
        tester,
        ErrorView(
          error: DioException(
            requestOptions: options,
            response: Response(
              requestOptions: options,
              statusCode: 403,
              data: '<html>challenge</html>',
              headers: Headers.fromMap({
                'cf-mitigated': ['challenge'],
              }),
            ),
          ),
        ),
      );
      expect(find.text(S.current.cf_manualVerifyAction), findsOneWidget);
      await unmount(tester);
    },
  );
}
