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

/// Attach both outcomes before pumping. Assertions remain outside callbacks so
/// Flutter's guarded pump and expect APIs never overlap across async zones.
class _Pending<T> {
  _Pending(Future<T> future) {
    unawaited(
      future.then<void>(
        (value) {
          result = value;
          complete = true;
        },
        onError: (Object error, StackTrace stack) {
          failure = error;
          complete = true;
        },
      ),
    );
  }
  bool complete = false;
  T? result;
  Object? failure;
}

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
  final adapters = <_Adapter>[];
  var hostId = 0;
  late int maxConcurrent;
  late int maxPerWindow;
  setUpAll(platform.initialize);
  setUp(() async {
    await platform.reset();
    cf.resetCooldown();
    cf.autoVerifyEnabled = true;
    adapters.clear();
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

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition,
    String reason,
  ) async {
    // Dio dispatch uses event-queue futures. Advancing fake time drains those
    // too; pump() without a duration drains only microtasks. Never await a
    // request directly while its event queue is frozen.
    for (var i = 0; i < 300 && !condition(); i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue, reason: reason);
  }

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
    final verification = _Pending(cf.showAutomaticVerify());
    await pumpUntil(
      tester,
      () => platform.webView != null || verification.complete,
      'verification should create a page or return a result',
    );
    expect(verification.failure, isNull);
    expect(cf.isVerifying, isTrue);
    expect(platform.webView, isNotNull);
  }

  Future<void> finish(WidgetTester tester, {bool success = true}) async {
    tester.widget<CfChallengePage>(find.byType(CfChallengePage)).onResult!(
      success,
    );
    await pumpUntil(
      tester,
      () => !cf.isVerifying,
      'verification should finish its native teardown and readiness gate',
    );
  }

  Future<void> runCase(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    try {
      await body();
    } finally {
      // Failure must not poison the singleton verification or leave a reserved
      // scheduler slot for the next case. Finish all controlled adapter waits.
      for (final adapter in adapters) {
        final pending = adapter.holdFirst;
        if (pending != null && !pending.isCompleted) pending.complete();
      }
      await tester.pump(const Duration(milliseconds: 10));
      final pages = find.byType(CfChallengePage);
      if (pages.evaluate().isNotEmpty) {
        tester.widget<CfChallengePage>(pages.first).onResult?.call(false);
      }
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox.shrink());
      cf.resetCooldown();
    }
  }

  Dio client(_Adapter adapter, {bool manageCookies = true}) {
    adapters.add(adapter);
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

  testWidgets(
    'pending GET/HEAD resume once with fresh cookies; writes and polls do not',
    (tester) => runCase(tester, () async {
      await mount(tester);
      final adapter = _Adapter();
      final dio = client(adapter);
      await start(tester);
      final read = _Pending(
        dio.get(
          '/read',
          options: Options(headers: {'Cookie': 'cf_clearance=old'}),
        ),
      );
      final head = _Pending(dio.head('/head'));
      final post = _Pending(dio.post('/write'));
      final poll = _Pending(
        dio.get('/poll', options: Options(extra: {'isSilent': true})),
      );
      await pumpUntil(
        tester,
        () => post.complete && poll.complete,
        'writes and silent polling should fail promptly during verification',
      );
      expect(adapter.requests, isEmpty);
      expect(read.complete, isFalse);
      expect(head.complete, isFalse);
      expect((post.failure as DioException).error, isA<CfChallengeException>());
      expect((poll.failure as DioException).error, isA<CfChallengeException>());
      await jar.cookieJar.saveFromResponse(Uri.parse(dio.options.baseUrl), [
        io.Cookie('cf_clearance', 'fresh'),
      ]);
      await finish(tester);
      await pumpUntil(
        tester,
        () => read.complete && head.complete,
        'both queued reads should complete after verification readiness',
      );
      expect(read.failure, isNull);
      expect(head.failure, isNull);
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
    }),
  );

  testWidgets(
    'a client without CookieManager preserves caller credentials after waiting',
    (tester) => runCase(tester, () async {
      await mount(tester);
      final adapter = _Adapter();
      final dio = client(adapter, manageCookies: false);
      await start(tester);
      final request = _Pending(
        dio.get(
          '/independent',
          options: Options(headers: {'Cookie': 'caller-session=preserved'}),
        ),
      );
      await tester.pump(const Duration(milliseconds: 10));
      expect(adapter.requests, isEmpty);
      expect(request.complete, isFalse);
      await finish(tester);
      await pumpUntil(
        tester,
        () => request.complete,
        'independent read should resume',
      );
      expect(request.failure, isNull);
      expect(
        adapter.requests.single.headers['Cookie'],
        'caller-session=preserved',
      );
    }),
  );

  testWidgets(
    'CF starting while queued releases the reserved slot before waiting',
    (tester) => runCase(tester, () async {
      await mount(tester);
      final adapter = _Adapter()..holdFirst = Completer<void>();
      final dio = client(adapter);
      final first = _Pending(dio.get('/first'));
      await pumpUntil(
        tester,
        () => adapter.requests.length == 1,
        'first read should reserve the only scheduler slot',
      );
      final queued = _Pending(dio.get('/queued'));
      await tester.pump(const Duration(milliseconds: 10));
      expect(adapter.requests.length, 1);
      await start(tester);
      adapter.holdFirst!.complete();
      await pumpUntil(
        tester,
        () => first.complete,
        'first read should release its slot',
      );
      expect(first.failure, isNull);
      expect(
        adapter.requests.length,
        1,
        reason: 'queued read cannot leak through CF',
      );
      final retry = _Pending(
        dio.get(
          '/original-retry',
          options: Options(extra: {'skipCfBlock': true}),
        ),
      );
      await pumpUntil(
        tester,
        () => retry.complete,
        'deferred read must release its reserved slot for the original retry',
      );
      expect(retry.failure, isNull);
      expect(adapter.requests.length, 2);
      await finish(tester);
      await pumpUntil(
        tester,
        () => queued.complete,
        'queued read should resume after CF',
      );
      expect(queued.failure, isNull);
      expect(adapter.requests.map((r) => r.path), [
        '/first',
        '/original-retry',
        '/queued',
      ]);
    }),
  );

  testWidgets(
    'CF beginning during the browser-trust await is checked before admission',
    (tester) => runCase(tester, () async {
      await mount(tester);
      final scheduler = RequestSchedulerInterceptor();
      final options = RequestOptions(path: 'https://cf-trust-await.test/read');
      final handler = RequestInterceptorHandler();
      // ignore: invalid_use_of_protected_member
      final admission = _Pending(handler.future);
      scheduler.onRequest(options, handler);
      // onRequest has yielded at its browser-trust wait. Start this round before
      // that continuation can admit the request into the scheduler.
      final verification = _Pending(cf.showAutomaticVerify());
      await pumpUntil(
        tester,
        () => platform.webView != null || verification.complete,
        'the overlapping verification should create its page',
      );
      expect(verification.failure, isNull);
      expect(cf.isVerifying, isTrue);
      expect(admission.complete, isFalse);
      await finish(tester);
      await pumpUntil(
        tester,
        () => admission.complete,
        'request should be admitted after the overlapping round finishes',
      );
      expect(admission.failure, isNull);
      scheduler.onResponse(
        Response(requestOptions: options),
        ResponseInterceptorHandler(),
      );
    }),
  );

  testWidgets(
    'cancelled and failed verification waiters never reach the adapter',
    (tester) => runCase(tester, () async {
      await mount(tester);
      final adapter = _Adapter();
      final dio = client(adapter);
      await start(tester);
      final cancel = CancelToken();
      final cancelled = _Pending(dio.get('/cancelled', cancelToken: cancel));
      final failed = _Pending(dio.get('/failed'));
      await tester.pump(const Duration(milliseconds: 10));
      cancel.cancel('left page');
      await pumpUntil(
        tester,
        () => cancelled.complete,
        'cancelled read should terminate promptly',
      );
      expect((cancelled.failure as DioException).type, DioExceptionType.cancel);
      await finish(tester, success: false);
      await pumpUntil(
        tester,
        () => failed.complete,
        'failed verification should release its waiter',
      );
      expect(
        (failed.failure as DioException).error,
        isA<CfChallengeException>(),
      );
      expect(adapter.requests, isEmpty);
    }),
  );
}
