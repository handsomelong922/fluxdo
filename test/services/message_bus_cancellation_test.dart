import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/message_bus_service.dart';

/// 请求被取消后仍由测试显式结束，模拟平台网络层的异步收尾。
class _ControlledDio implements Dio {
  final requests =
      <({CancelToken token, Completer<Response<dynamic>> result})>[];

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final result = Completer<Response<dynamic>>();
    requests.add((token: cancelToken!, result: result));
    return (await result.future) as Response<T>;
  }

  void finishCancelled(int index) {
    requests[index].result.completeError(
      DioException(
        requestOptions: RequestOptions(path: '/poll'),
        type: DioExceptionType.cancel,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('旧会话收尾后，新会话的在途轮询仍能取消', () async {
    final dio = _ControlledDio();
    final bus = MessageBusService.forTesting(dio);
    addTearDown(bus.dispose);

    bus.subscribe('/old', (_) {});
    expect(dio.requests, hasLength(1));
    bus.stopAll();
    expect(dio.requests[0].token.isCancelled, isTrue);

    bus.subscribe('/new', (_) {});
    expect(dio.requests, hasLength(2));
    expect(dio.requests[1].token.isCancelled, isFalse);

    // 旧请求迟于新轮询启动结束。修复前此处会清空新请求的令牌。
    dio.finishCancelled(0);
    await Future<void>.delayed(Duration.zero);
    bus.stopAll();
    expect(dio.requests[1].token.isCancelled, isTrue);

    dio.finishCancelled(1);
    await Future<void>.delayed(Duration.zero);
    expect(dio.requests, hasLength(2));
  });

  test('正常停止同样取消当前轮询且不自行重启', () async {
    final dio = _ControlledDio();
    final bus = MessageBusService.forTesting(dio);
    addTearDown(bus.dispose);
    bus.subscribe('/current', (_) {});
    bus.stopAll();
    expect(dio.requests.single.token.isCancelled, isTrue);
    dio.finishCancelled(0);
    await Future<void>.delayed(Duration.zero);
    expect(dio.requests, hasLength(1));
  });
}
