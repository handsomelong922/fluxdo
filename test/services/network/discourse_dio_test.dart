import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/discourse_dio.dart';
import 'package:fluxdo/services/network/interceptors/error_interceptor.dart';
import 'package:fluxdo/services/network/interceptors/request_scheduler_interceptor.dart';
import 'package:fluxdo/services/network/request_scheduler_config.dart';

void main() {
  group('shouldRetryDiscourseRequest', () {
    RequestOptions options(String method) =>
        RequestOptions(path: '/latest.json', method: method);

    test('retries transient read request failures', () {
      expect(
        shouldRetryDiscourseRequest(
          DioException.connectionError(
            requestOptions: options('GET'),
            reason: 'socket closed',
          ),
          1,
        ),
        isTrue,
      );

      expect(
        shouldRetryDiscourseRequest(
          DioException(
            requestOptions: options('HEAD'),
            type: DioExceptionType.receiveTimeout,
          ),
          1,
        ),
        isTrue,
      );
    });

    test('retries selected read response statuses', () {
      for (final statusCode in [408, 502, 503, 504]) {
        final requestOptions = options('GET');

        expect(
          shouldRetryDiscourseRequest(
            DioException.badResponse(
              statusCode: statusCode,
              requestOptions: requestOptions,
              response: Response(
                requestOptions: requestOptions,
                statusCode: statusCode,
              ),
            ),
            1,
          ),
          isTrue,
        );
      }
    });

    test('does not retry rate limits', () {
      final requestOptions = options('GET');

      expect(
        shouldRetryDiscourseRequest(
          DioException.badResponse(
            statusCode: 429,
            requestOptions: requestOptions,
            response: Response(requestOptions: requestOptions, statusCode: 429),
          ),
          1,
        ),
        isFalse,
      );
    });

    test('does not retry write requests', () {
      expect(
        shouldRetryDiscourseRequest(
          DioException.connectionError(
            requestOptions: options('POST'),
            reason: 'socket closed',
          ),
          1,
        ),
        isFalse,
      );
    });

    test('honors the per-request automatic retry opt out', () {
      final requestOptions = options('GET');
      requestOptions.extra[disableAutomaticRetryExtraKey] = true;

      expect(
        shouldRetryDiscourseRequest(
          DioException.connectionError(
            requestOptions: requestOptions,
            reason: 'socket closed',
          ),
          1,
        ),
        isFalse,
      );
    });

    test('does not retry definitive failures', () {
      expect(
        shouldRetryDiscourseRequest(
          DioException(
            requestOptions: options('GET'),
            type: DioExceptionType.cancel,
          ),
          1,
        ),
        isFalse,
      );

      expect(
        shouldRetryDiscourseRequest(
          DioException(
            requestOptions: options('GET'),
            type: DioExceptionType.badCertificate,
            error: const CertificateException('bad cert'),
          ),
          1,
        ),
        isFalse,
      );
    });
  });

  group('RequestSchedulerConfig', () {
    tearDown(() {
      RequestSchedulerConfig.resetServerCooldownForTesting();
    });

    test(
      'pauses new requests after server rate limits and clears after expiry',
      () async {
        RequestSchedulerConfig.pauseFor(const Duration(milliseconds: 30));

        expect(
          RequestSchedulerConfig.serverCooldownRemaining.inMicroseconds,
          greaterThan(0),
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(RequestSchedulerConfig.serverCooldownRemaining, Duration.zero);
      },
    );
  });

  group('ErrorInterceptor', () {
    tearDown(() {
      RequestSchedulerConfig.resetServerCooldownForTesting();
    });

    test('silent rate limits still pause the shared scheduler', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://linux.do'));
      dio.httpClientAdapter = _StatusAdapter(
        statusCode: 429,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
          'retry-after': ['3'],
        },
      );
      dio.interceptors.add(ErrorInterceptor());

      await expectLater(
        dio.get('/latest.json', options: Options(extra: {'isSilent': true})),
        throwsA(isA<DioException>()),
      );

      expect(
        RequestSchedulerConfig.serverCooldownRemaining.inMicroseconds,
        greaterThan(0),
      );
    });
  });

  group('RequestSchedulerInterceptor', () {
    late int previousMaxConcurrent;
    late int previousMaxPerWindow;
    late int previousWindowSeconds;
    late int previousMinIntervalMs;

    setUp(() {
      previousMaxConcurrent = RequestSchedulerConfig.maxConcurrent;
      previousMaxPerWindow = RequestSchedulerConfig.maxPerWindow;
      previousWindowSeconds = RequestSchedulerConfig.windowSeconds;
      previousMinIntervalMs = RequestSchedulerConfig.minIntervalMs;
      RequestSchedulerInterceptor.resetSharedStateForTesting();
      RequestSchedulerConfig.maxConcurrent = 1;
      RequestSchedulerConfig.maxPerWindow = 100;
      RequestSchedulerConfig.windowSeconds = 1;
      RequestSchedulerConfig.minIntervalMs = 0;
    });

    tearDown(() {
      RequestSchedulerConfig.maxConcurrent = previousMaxConcurrent;
      RequestSchedulerConfig.maxPerWindow = previousMaxPerWindow;
      RequestSchedulerConfig.windowSeconds = previousWindowSeconds;
      RequestSchedulerConfig.minIntervalMs = previousMinIntervalMs;
      RequestSchedulerInterceptor.resetSharedStateForTesting();
    });

    test('shares concurrency by host across dio instances', () async {
      final adapter = _ConcurrencyRecordingAdapter(
        delay: const Duration(milliseconds: 30),
      );

      Dio createDio() {
        final dio = Dio(BaseOptions(baseUrl: 'https://linux.do'));
        dio.httpClientAdapter = adapter;
        dio.interceptors.add(RequestSchedulerInterceptor());
        return dio;
      }

      await Future.wait([
        createDio().get('/latest.json'),
        createDio().get('/hot.json'),
      ]);

      expect(adapter.maxActive, 1);
      expect(adapter.completedRequests, 2);
    });

    test('low priority background requests yield to normal requests', () async {
      final adapter = _GatedOrderRecordingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://linux.do'));
      dio.httpClientAdapter = adapter;
      dio.interceptors.add(RequestSchedulerInterceptor());

      final first = dio.get(
        '/first',
        options: Options(extra: {'skipBrowserTrustGate': true}),
      );
      await adapter.firstRequestStarted;
      final low = dio.get(
        '/low',
        options: Options(
          extra: {'priority': 'low', 'skipBrowserTrustGate': true},
        ),
      );
      final normal = dio.get(
        '/normal',
        options: Options(extra: {'skipBrowserTrustGate': true}),
      );
      await pumpEventQueue();
      adapter.releaseFirstRequest();

      await Future.wait([first, low, normal]);

      expect(adapter.completedPaths, ['/first', '/normal', '/low']);
    });

    test(
      'high priority foreground requests jump ahead of queued reads',
      () async {
        final adapter = _GatedOrderRecordingAdapter();
        final dio = Dio(BaseOptions(baseUrl: 'https://linux.do'));
        dio.httpClientAdapter = adapter;
        dio.interceptors.add(RequestSchedulerInterceptor());

        final first = dio.get(
          '/first',
          options: Options(extra: {'skipBrowserTrustGate': true}),
        );
        await adapter.firstRequestStarted;
        final low = dio.get(
          '/low',
          options: Options(
            extra: {'priority': 'low', 'skipBrowserTrustGate': true},
          ),
        );
        final normal = dio.get(
          '/normal',
          options: Options(extra: {'skipBrowserTrustGate': true}),
        );
        final high = dio.get(
          '/topic-detail',
          options: Options(
            extra: {'priority': 'high', 'skipBrowserTrustGate': true},
          ),
        );
        await pumpEventQueue();
        adapter.releaseFirstRequest();

        await Future.wait([first, low, normal, high]);

        expect(adapter.completedPaths, [
          '/first',
          '/topic-detail',
          '/normal',
          '/low',
        ]);
      },
    );

    test(
      'spaces consecutive requests by configured minimum interval',
      () async {
        RequestSchedulerConfig.maxConcurrent = 10;
        RequestSchedulerConfig.minIntervalMs = 35;
        final adapter = _StartTimeRecordingAdapter();
        final dio = Dio(BaseOptions(baseUrl: 'https://linux.do'));
        dio.httpClientAdapter = adapter;
        dio.interceptors.add(RequestSchedulerInterceptor());

        await Future.wait([dio.get('/first'), dio.get('/second')]);

        expect(adapter.startTimes, hasLength(2));
        expect(
          adapter.startTimes[1]
              .difference(adapter.startTimes[0])
              .inMilliseconds,
          greaterThanOrEqualTo(25),
        );
      },
    );
  });
}

class _StartTimeRecordingAdapter implements HttpClientAdapter {
  final List<DateTime> startTimes = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    startTimes.add(DateTime.now());
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ConcurrencyRecordingAdapter implements HttpClientAdapter {
  _ConcurrencyRecordingAdapter({required this.delay});

  final Duration delay;
  int active = 0;
  int maxActive = 0;
  int completedRequests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    active++;
    if (active > maxActive) maxActive = active;
    try {
      await Future<void>.delayed(delay);
      completedRequests++;
      return ResponseBody.fromString(
        '{}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    } finally {
      active--;
    }
  }

  @override
  void close({bool force = false}) {}
}

class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter({required this.statusCode, this.headers = const {}});

  final int statusCode;
  final Map<String, List<String>> headers;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString('{}', statusCode, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

class _GatedOrderRecordingAdapter implements HttpClientAdapter {
  final List<String> completedPaths = [];
  final Completer<void> _firstRequestStarted = Completer<void>();
  final Completer<void> _releaseFirstRequest = Completer<void>();

  Future<void> get firstRequestStarted => _firstRequestStarted.future;

  void releaseFirstRequest() {
    if (!_releaseFirstRequest.isCompleted) {
      _releaseFirstRequest.complete();
    }
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/first' && !_firstRequestStarted.isCompleted) {
      _firstRequestStarted.complete();
      await _releaseFirstRequest.future;
    }
    completedPaths.add(options.path);
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
