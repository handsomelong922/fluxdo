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
  final pendingSnapshots = <Completer<Cookie?>>[];
  setUpAll(platform.initialize);
  setUp(() async {
    await platform.reset();
    cf.resetCooldown();
    pendingSnapshots.clear();
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

  Future<void> runCase(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    try {
      await body();
    } finally {
      // Keep one failed assertion from leaving a pending round or Toast overlay
      // behind for the next case. Resolve only test-controlled snapshots.
      for (final snapshot in pendingSnapshots) {
        if (!snapshot.isCompleted) snapshot.complete(null);
      }
      await tester.pump(const Duration(milliseconds: 10));
      final pages = find.byType(CfChallengePage);
      if (pages.evaluate().isNotEmpty) {
        tester.widget<CfChallengePage>(pages.first).onResult?.call(false);
      }
      await tester.pump(const Duration(seconds: 2));
      await unmount(tester);
      cf.resetCooldown();
    }
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
    (tester) => runCase(tester, () async {
      var retries = 0;
      bool? verifyingAtRetry;
      await mount(
        tester,
        ErrorView(
          error: CfChallengeException(autoVerifyDisabled: true),
          onRetry: () {
            verifyingAtRetry = cf.isVerifying;
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
      pendingSnapshots.add(snapshot);
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
      expect(verifyingAtRetry, isFalse);
      await tester.pump(const Duration(milliseconds: 400));
    }),
  );

  testWidgets(
    'rendered replacement error is not retried by verification completion',
    (tester) => runCase(tester, () async {
      var originalRetries = 0;
      var replacementRetries = 0;
      Object error = CfChallengeException(autoVerifyDisabled: true);
      VoidCallback retry = () => originalRetries++;
      late StateSetter rebuild;
      await mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return ErrorView(error: error, onRetry: retry);
          },
        ),
      );
      await start(tester);
      final originalState = tester.state(find.byType(ErrorView));
      final replacementError = StateError('newer request failed');
      rebuild(() {
        error = replacementError;
        retry = () => replacementRetries++;
      });
      // setState only schedules a frame. Deliver the replacement before
      // completing verification; a long pump elapses timers before building.
      await tester.pump();
      expect(
        tester.widget<ErrorView>(find.byType(ErrorView)).error,
        same(replacementError),
      );
      expect(tester.state(find.byType(ErrorView)), same(originalState));
      finish();
      await tester.pump(const Duration(seconds: 2));
      expect(cf.isVerifying, isFalse);
      expect(originalRetries, 0);
      expect(replacementRetries, 0);
    }),
  );

  testWidgets(
    'replacement during cookie readiness is not retried by late success',
    (tester) => runCase(tester, () async {
      var originalRetries = 0;
      var replacementRetries = 0;
      Object error = CfChallengeException(autoVerifyDisabled: true);
      VoidCallback retry = () => originalRetries++;
      late StateSetter rebuild;
      await mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return ErrorView(error: error, onRetry: retry);
          },
        ),
      );
      await start(tester);
      final originalState = tester.state(find.byType(ErrorView));
      final snapshot = Completer<Cookie?>();
      pendingSnapshots.add(snapshot);
      platform.cookies.readValue = (_) => snapshot.future;
      platform.cookies.values = [cfTestCookie('verified')];
      finish();
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(CfChallengePage), findsNothing);
      expect(
        cf.isVerifying,
        isTrue,
        reason: 'successful page teardown still waits for its Cookie snapshot',
      );
      expect(snapshot.isCompleted, isFalse);
      expect(originalRetries, 0);

      final replacementError = StateError('request replaced while syncing');
      rebuild(() {
        error = replacementError;
        retry = () => replacementRetries++;
      });
      await tester.pump();
      expect(
        tester.widget<ErrorView>(find.byType(ErrorView)).error,
        same(replacementError),
      );
      expect(tester.state(find.byType(ErrorView)), same(originalState));
      snapshot.complete(cfTestCookie('verified'));
      for (var i = 0; i < 30 && cf.isVerifying; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(
        cf.isVerifying,
        isFalse,
        reason: 'controlled snapshot completion must release readiness',
      );
      expect(await CookieJarService().getCfClearance(), 'verified');
      expect(originalRetries, 0);
      expect(replacementRetries, 0);
    }),
  );

  testWidgets(
    'failed verification never retries',
    (tester) => runCase(tester, () async {
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
    }),
  );

  testWidgets(
    'raw CF challenge after a bounded retry offers manual verification',
    (tester) => runCase(tester, () async {
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
    }),
  );
}
