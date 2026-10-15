import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/services/auth_session.dart';
import 'package:fluxdo/services/cf_clearance_refresh_service.dart';
import 'package:fluxdo/services/cf_challenge_service.dart';
import 'package:fluxdo/services/local_notification_service.dart'
    show navigatorKey;
import 'package:fluxdo/services/network/cookie/cookie_jar_service.dart';
import 'package:fluxdo/services/network/interceptors/cf_challenge_interceptor.dart';
import 'package:fluxdo/services/network/system_proxy_service.dart';

import '../../../support/cf_test_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = CfTestPlatform();
  final jar = CookieJarService();
  final cfService = CfChallengeService();

  setUpAll(platform.initialize);
  setUp(() async {
    await platform.reset();
    cfService.resetCooldown();
    cfService.autoVerifyEnabled = true;
    cfService.clearanceResolvedAt.value = null;
  });
  tearDown(() async {
    cfService.resetCooldown();
    SystemProxyService.instance.resetForTest();
    await platform.reset();
  });

  for (final (method, challenge) in [
    ('GET', false),
    ('POST', true),
    ('PUT', true),
    ('PATCH', true),
    ('DELETE', true),
  ]) {
    test('503 $method 挑战=$challenge 不扩大写请求恢复或误判普通故障', () async {
      final adapter = _ChallengeAdapter(200);
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final options = RequestOptions(
        path: 'https://linux.do/posts',
        method: method,
      );
      final error = DioException(
        requestOptions: options,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: 503,
          data: '<html>Service unavailable</html>',
          headers: Headers.fromMap({
            if (challenge) 'cf-mitigated': ['challenge'],
          }),
        ),
      );
      final handler = _RecordingErrorHandler();
      final round = cfService.verifyRound;
      await CfChallengeInterceptor(
        dio: dio,
        cookieJarService: jar,
      ).onError(error, handler);
      expect(handler.forwarded, same(error));
      expect(adapter.requests, 0);
      expect(cfService.verifyRound, round);
      expect(platform.webView, isNull);
    });
  }

  for (final cancelledBy in ['token', 'error', 'session']) {
    test('迟到的挑战在 $cancelledBy 取消后不启动验证或重放', () async {
      final adapter = _ChallengeAdapter(200);
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final token = CancelToken();
      if (cancelledBy == 'token') token.cancel('startup disposed');
      final options = RequestOptions(
        path: 'https://linux.do/latest.json',
        cancelToken: token,
        extra: {
          '_sessionGeneration':
              AuthSession().generation - (cancelledBy == 'session' ? 1 : 0),
        },
      );
      final handler = _RecordingErrorHandler();
      final round = cfService.verifyRound;
      final sitekey = CfClearanceRefreshService().sitekey;
      await CfChallengeInterceptor(dio: dio, cookieJarService: jar).onError(
        DioException(
          requestOptions: options,
          type: cancelledBy == 'error'
              ? DioExceptionType.cancel
              : DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: options,
            statusCode: 403,
            headers: Headers.fromMap({
              'cf-mitigated': ['challenge'],
            }),
            data: '<html>challenge</html>',
          ),
        ),
        handler,
      );
      expect(handler.forwarded?.type, DioExceptionType.cancel);
      expect(handler.calls, 1);
      expect(adapter.requests, 0);
      expect(cfService.verifyRound, round);
      expect(cfService.isVerifying, isFalse);
      expect(platform.webView, isNull);
      expect(CfClearanceRefreshService().sitekey, sitekey);
    });
  }

  for (final (
        initialStatus,
        retryStatus,
        delayedSnapshot,
        isSilent,
        cancelBeforeReady,
      )
      in [
        (403, 200, false, true, false),
        (503, 200, false, true, false),
        (503, 503, false, true, false),
        (403, 403, false, true, false),
        (403, 200, true, true, false),
        (403, 200, false, false, false),
        (403, 200, false, true, true),
      ]) {
    testWidgets(
      '初始 $initialStatus 入口无盾后以 API $retryStatus 判断恢复（快照延迟=$delayedSnapshot，静默=$isSilent，取消=$cancelBeforeReady）',
      (tester) async {
        await tester.pumpWidget(
          TranslationProvider(
            child: MaterialApp(
              navigatorKey: navigatorKey,
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocaleUtils.supportedLocales,
              home: const Scaffold(body: SizedBox.shrink()),
            ),
          ),
        );

        final adapter = _ChallengeAdapter(
          retryStatus,
          initialStatus: initialStatus,
        );
        final dio = Dio(BaseOptions(baseUrl: 'https://linux.do'))
          ..httpClientAdapter = adapter;
        dio.interceptors.add(
          CfChallengeInterceptor(dio: dio, cookieJarService: jar),
        );
        addTearDown(() => dio.close(force: true));

        Response<dynamic>? result;
        Object? failure;
        var completed = false;
        final cancelToken = CancelToken();
        final request = dio
            .get<dynamic>(
              '/latest.json',
              cancelToken: cancelToken,
              options: Options(extra: {'isSilent': isSilent}),
            )
            .then<void>(
              (response) {
                result = response;
                completed = true;
              },
              onError: (Object error) {
                failure = error;
                completed = true;
              },
            );

        for (var i = 0; i < 20 && platform.webView == null; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(platform.webView, isNotNull);
        final verifyPage = tester.widget<CfChallengePage>(
          find.byType(CfChallengePage),
        );
        expect(verifyPage.startInBackground, isTrue);
        expect(verifyPage.quietBackground, isTrue);
        expect(find.text(S.current.cf_securityVerifyTitle), findsNothing);
        expect(find.text(S.current.cf_backgroundVerifying), findsNothing);
        platform.webView!.params.onWebViewCreated!(platform.controller.wrapped);
        Completer<Cookie?>? pendingValue;
        if (delayedSnapshot) {
          // 验证期间另一路先写回了副本，验证页的 Cookie 快照此刻尚在读取。
          await jar.cookieJar.saveFromResponse(Uri.parse('https://linux.do'), [
            io.Cookie('cf_clearance', 'bootstrap-copy')
              ..domain = '.linux.do'
              ..path = '/',
          ]);
          pendingValue = Completer<Cookie?>();
          platform.cookies.readValue = (_) => pendingValue!.future;
          platform.cookies.values = [cfTestCookie('current-webview-value')];
        }
        platform.webView!.params.onReceivedHttpError!(
          platform.controller.wrapped,
          WebResourceRequest(
            url: WebUri('https://linux.do/challenge'),
            isForMainFrame: true,
          ),
          WebResourceResponse(statusCode: 404),
        );
        if (pendingValue != null) {
          await tester.pump(const Duration(milliseconds: 10));
          expect(
            cfService.clearanceResolvedAt.value,
            isNotNull,
            reason: '入口无盾即可结束页面，不被当前快照读取阻塞',
          );
          expect(adapter.requests, 1, reason: '原生重试需复用当前快照，不能抢发旧 jar');
          pendingValue.complete(cfTestCookie('current-webview-value'));
        }
        if (cancelBeforeReady) cancelToken.cancel('left page');
        await tester.pump(const Duration(milliseconds: 100));
        expect(adapter.requests, 1, reason: '页面结束后仍需等待原生析构闸门');
        await tester.pump(const Duration(milliseconds: 1200));
        for (var i = 0; i < 20 && !completed; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }

        expect(completed, isTrue, reason: 'Cookie 快照和析构完成后立即重试，不轮询新 Cookie');
        await request;
        expect(adapter.requests, cancelBeforeReady ? 1 : 2);
        expect(
          await jar.getCfClearance(),
          delayedSnapshot ? 'current-webview-value' : isNull,
        );
        if (delayedSnapshot) {
          expect(
            adapter.lastCookieHeader,
            contains('cf_clearance=current-webview-value'),
          );
        }
        if (cancelBeforeReady) {
          expect(result, isNull);
          expect(failure, isA<DioException>());
          expect((failure as DioException).type, DioExceptionType.cancel);
          expect(cfService.isInCooldown, isFalse);
        } else if (retryStatus == 200) {
          expect(result?.statusCode, 200);
          expect(failure, isNull);
          expect(cfService.consecutiveFailures, 0);
          expect(cfService.isInCooldown, isFalse);
        } else {
          expect(result, isNull);
          expect(failure, isA<DioException>());
          expect((failure as DioException).response?.statusCode, retryStatus);
          expect(cfService.isInCooldown, isTrue);
        }

        // 清理验证页面的原生析构冷却和续期服务启动定时器。
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

class _ChallengeAdapter implements HttpClientAdapter {
  _ChallengeAdapter(this.retryStatus, {this.initialStatus = 403});

  final int initialStatus;

  final int retryStatus;
  int requests = 0;
  String? lastCookieHeader;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastCookieHeader = options.headers['Cookie']?.toString();
    final status = ++requests == 1 ? initialStatus : retryStatus;
    final challenged = status == 403 || status == 503;
    return ResponseBody.fromString(
      challenged ? '<html>challenge</html>' : '{}',
      status,
      headers: {
        Headers.contentTypeHeader: [
          challenged ? 'text/html' : 'application/json',
        ],
        if (challenged) 'cf-mitigated': ['challenge'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _RecordingErrorHandler extends ErrorInterceptorHandler {
  DioException? forwarded;
  int calls = 0;

  @override
  void next(DioException error) {
    forwarded = error;
    calls++;
  }
}
