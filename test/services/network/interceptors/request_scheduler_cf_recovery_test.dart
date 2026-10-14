import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/services/cf_challenge_service.dart';
import 'package:fluxdo/services/local_notification_service.dart'
    show navigatorKey;
import 'package:fluxdo/services/network/cookie/app_cookie_manager.dart';
import 'package:fluxdo/services/network/cookie/cookie_jar_service.dart';
import 'package:fluxdo/services/network/exceptions/api_exception.dart';
import 'package:fluxdo/services/network/interceptors/request_scheduler_interceptor.dart';
import 'package:fluxdo/services/network/request_scheduler_config.dart';

import '../../../support/cf_test_platform.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Completer<void>? holdFirst;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requests.length == 1) await holdFirst?.future;
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = CfTestPlatform();
  final cf = CfChallengeService();
  final jar = CookieJarService();
  var hostId = 0;
  late int maxConcurrent;
  late int maxPerWindow;
  setUpAll(platform.initialize);
  setUp(() async {
    await platform.reset();
    cf.resetCooldown();
    cf.autoVerifyEnabled = true;
    maxConcurrent = RequestSchedulerConfig.maxConcurrent;
    maxPerWindow = RequestSchedulerConfig.maxPerWindow;
    RequestSchedulerConfig.maxConcurrent = 1;
    RequestSchedulerConfig.maxPerWindow = 1000;
  });
  tearDown(() async {
    RequestSchedulerConfig.maxConcurrent = maxConcurrent;
    RequestSchedulerConfig.maxPerWindow = maxPerWindow;
    await platform.reset();
  });

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
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

  Future<void> start(WidgetTester tester) async {
    unawaited(cf.showAutomaticVerify());
    for (var i = 0; i < 20 && platform.webView == null; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(cf.isVerifying, isTrue);
    expect(platform.webView, isNotNull);
  }

  Future<void> finish(WidgetTester tester, {bool success = true}) async {
    tester.widget<CfChallengePage>(find.byType(CfChallengePage)).onResult!(
      success,
    );
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
  }

  Dio client(_Adapter adapter, {bool manageCookies = true}) {
    final dio =
        Dio(BaseOptions(baseUrl: 'https://cf-scheduler-${hostId++}.test'))
          ..httpClientAdapter = adapter
          ..interceptors.addAll([
            RequestSchedulerInterceptor(),
            if (manageCookies) AppCookieManager(jar.cookieJar),
          ]);
    addTearDown(() => dio.close(force: true));
    return dio;
  }

  Future<Object?> failure(Future<Response<dynamic>> request) =>
      request.then<Object?>((_) => null, onError: (Object error) => error);

  testWidgets(
    'pending GET/HEAD resume once with fresh cookies; writes and polls do not',
    (tester) async {
      await mount(tester);
      final adapter = _Adapter();
      final dio = client(adapter);
      await start(tester);
      final read = dio.get(
        '/read',
        options: Options(headers: {'Cookie': 'cf_clearance=old'}),
      );
      final head = dio.head('/head');
      final post = failure(dio.post('/write'));
      final poll = failure(
        dio.get('/poll', options: Options(extra: {'isSilent': true})),
      );
      await tester.pump();
      expect(adapter.requests, isEmpty);
      expect((await post as DioException).error, isA<CfChallengeException>());
      expect((await poll as DioException).error, isA<CfChallengeException>());
      await jar.cookieJar.saveFromResponse(Uri.parse(dio.options.baseUrl), [
        io.Cookie('cf_clearance', 'fresh'),
      ]);
      await finish(tester);
      await read;
      await head;
      expect(adapter.requests.map((r) => r.path), ['/read', '/head']);
      expect(
        adapter.requests.first.headers['cookie'],
        contains('cf_clearance=fresh'),
      );
      expect(
        adapter.requests.first.headers.values.any(
          (v) => '$v'.contains('cf_clearance=old'),
        ),
        isFalse,
      );
      expect(
        adapter.requests.every((r) => r.extra['skipCfChallenge'] == true),
        isTrue,
      );
      expect(
        adapter.requests.every((r) => r.extra['skipCfBlock'] != true),
        isTrue,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a client without CookieManager preserves caller credentials after waiting',
    (tester) async {
      await mount(tester);
      final adapter = _Adapter();
      final dio = client(adapter, manageCookies: false);
      await start(tester);
      final request = dio.get(
        '/independent',
        options: Options(headers: {'Cookie': 'caller-session=preserved'}),
      );
      await tester.pump();
      expect(adapter.requests, isEmpty);
      await finish(tester);
      await request;
      expect(
        adapter.requests.single.headers['Cookie'],
        'caller-session=preserved',
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'CF starting while queued releases the reserved slot before waiting',
    (tester) async {
      await mount(tester);
      final adapter = _Adapter()..holdFirst = Completer<void>();
      final dio = client(adapter);
      final first = dio.get('/first');
      await tester.pump();
      final queued = dio.get('/queued');
      await tester.pump();
      expect(adapter.requests.length, 1);
      await start(tester);
      adapter.holdFirst!.complete();
      await tester.pump();
      await first;
      expect(
        adapter.requests.length,
        1,
        reason: 'queued read cannot leak through CF',
      );
      final retry = dio.get(
        '/original-retry',
        options: Options(extra: {'skipCfBlock': true}),
      );
      await tester.pump();
      await retry;
      expect(
        adapter.requests.length,
        2,
        reason: 'deferred read must not hold the only slot',
      );
      await finish(tester);
      await queued;
      expect(adapter.requests.map((r) => r.path), [
        '/first',
        '/original-retry',
        '/queued',
      ]);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'CF beginning during the browser-trust await is checked before admission',
    (tester) async {
      await mount(tester);
      final scheduler = RequestSchedulerInterceptor();
      final options = RequestOptions(path: 'https://cf-trust-await.test/read');
      final handler = RequestInterceptorHandler();
      scheduler.onRequest(options, handler);
      // onRequest has yielded at its browser-trust wait. Start the round before
      // that continuation can admit the request into the scheduler.
      unawaited(cf.showAutomaticVerify());
      var admitted = false;
      unawaited(handler.future.then<void>((_) => admitted = true));
      await tester.pump();
      expect(cf.isVerifying, isTrue);
      expect(admitted, isFalse);
      await finish(tester);
      expect(admitted, isTrue);
      scheduler.onResponse(
        Response(requestOptions: options),
        ResponseInterceptorHandler(),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'cancelled and failed verification waiters never reach the adapter',
    (tester) async {
      await mount(tester);
      final adapter = _Adapter();
      final dio = client(adapter);
      await start(tester);
      final cancel = CancelToken();
      final cancelled = failure(dio.get('/cancelled', cancelToken: cancel));
      final failed = failure(dio.get('/failed'));
      await tester.pump();
      cancel.cancel('left page');
      await tester.pump();
      expect((await cancelled as DioException).type, DioExceptionType.cancel);
      await finish(tester, success: false);
      expect((await failed as DioException).error, isA<CfChallengeException>());
      expect(adapter.requests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
