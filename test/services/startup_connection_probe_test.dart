import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/flux_request_spec.dart';
import 'package:fluxdo/services/network/interceptors/error_interceptor.dart';
import 'package:fluxdo/services/network/recovery/recovery_coordinator.dart';
import 'package:fluxdo/services/network/recovery/recovery_policy.dart';
import 'package:fluxdo/services/startup_connection_probe.dart';

void main() {
  for (final status in [200, 403, 429]) {
    test(
      'startup read $status preserves request policy and never ordinary-retries',
      () async {
        final adapter = _Adapter(status);
        final policy = _PolicySpy();
        final dio = Dio(BaseOptions(baseUrl: 'https://linux.do'))
          ..httpClientAdapter = adapter;
        addTearDown(() => dio.close(force: true));
        dio.interceptors.addAll([
          RecoveryCoordinator(dio: dio, policies: [policy]),
          ErrorInterceptor(),
        ]);
        final token = CancelToken();
        final request = probeStartupConnection(dio, cancelToken: token);
        if (status == 200) {
          await request;
        } else {
          await expectLater(request, throwsA(isA<DioException>()));
        }
        expect(adapter.requests, 1);
        expect(policy.considered, 0);
        final options = adapter.options!;
        expect(options.method, 'GET');
        expect(options.path, '/latest.json');
        expect(identical(options.cancelToken, token), isTrue);
        expect(options.spec.isSilent, isFalse);
        expect(options.spec.skipCfChallenge, isFalse);
        expect(options.spec.skipCfBlock, isFalse);
        expect(options.spec.showErrorToast, isFalse);
        expect(options.spec.hasExplicitErrorToast, isTrue);
        expect(options.spec.skipAuthCheck, isTrue);
        expect(options.spec.skipCsrf, isTrue);
        expect(options.extra[FluxRequestKeys.skipSessionStateSync], isTrue);
        expect(options.spec.recoveryDisabled, isTrue);
        expect(
          options.extra[FluxRequestKeys.priority],
          FluxRequestPriority.low,
        );
        expect(options.sendTimeout, const Duration(seconds: 15));
        expect(options.receiveTimeout, const Duration(seconds: 15));
      },
    );
  }

  test('cancelled startup read never reaches transport', () async {
    final adapter = _Adapter(200);
    final dio = Dio(BaseOptions(baseUrl: 'https://linux.do'))
      ..httpClientAdapter = adapter;
    addTearDown(() => dio.close(force: true));
    final token = CancelToken()..cancel();
    await expectLater(
      probeStartupConnection(dio, cancelToken: token),
      throwsA(isA<DioException>()),
    );
    expect(adapter.requests, 0);
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status);
  final int status;
  int requests = 0;
  RequestOptions? options;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    this.options = options;
    return ResponseBody.fromString(
      '{"errors":["ordinary response"]}',
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _PolicySpy implements RecoveryPolicy {
  int considered = 0;
  @override
  String get name => 'startup-test-spy';
  @override
  bool canHandle(AttemptOutcome outcome) {
    considered++;
    return false;
  }

  @override
  Future<RecoveryDecision> decide(AttemptOutcome outcome) async =>
      const RecoveryDecision.complete();
}
