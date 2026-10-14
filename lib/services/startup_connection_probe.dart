import 'package:dio/dio.dart';

import 'network/flux_request_spec.dart';

/// 使用与刷帖相同的普通只读 API，不主动制造挑战或更新帖子阅读状态。
Future<void> probeStartupConnection(
  Dio dio, {
  required CancelToken cancelToken,
}) async {
  await dio.get<dynamic>(
    '/latest.json',
    cancelToken: cancelToken,
    options: Options(
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      extra: const {
        FluxRequestKeys.requestTag: 'startup-cf-warmup',
        FluxRequestKeys.priority: FluxRequestPriority.low,
        FluxRequestKeys.showErrorToast: false,
        FluxRequestKeys.skipAuthCheck: true,
        FluxRequestKeys.skipCsrf: true,
        FluxRequestKeys.skipSessionStateSync: true,
        FluxRequestKeys.noRecovery: true,
        // 不能 isSilent：真正命中 CF 时应复用既有后台验证与一次重放。
      },
    ),
  );
}
