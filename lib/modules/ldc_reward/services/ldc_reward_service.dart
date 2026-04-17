import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../services/network/discourse_dio.dart';
import '../../../l10n/s.dart';
import '../models/reward_request.dart';
import '../models/reward_result.dart';

/// LDC 打赏 API 服务
/// 复用 DiscourseDio（含 CF 验证拦截器），通过 Basic Auth header 认证
class LdcRewardService {
  static const String _distributeUrl = 'https://credit.linux.do/epay/pay/distribute';

  final String _authHeader;
  final Dio _dio;

  LdcRewardService({required String clientId, required String clientSecret})
      : _authHeader = 'Basic ${base64Encode(utf8.encode('$clientId:$clientSecret'))}',
        _dio = DiscourseDio.create();

  /// 执行打赏
  Future<LdcRewardResult> distribute(LdcRewardRequest request) async {
    try {
      final response = await _dio.post(
        _distributeUrl,
        data: request.toJson(),
        options: Options(
          headers: {
            'Authorization': _authHeader,
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return LdcRewardResult.fromResponse(response.data as Map<String, dynamic>);
      }

      return LdcRewardResult.error(S.current.reward_httpError(response.statusCode ?? 0));
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return LdcRewardResult.error(S.current.reward_authFailed);
      }
      if (e.response?.data is Map<String, dynamic>) {
        final msg = (e.response!.data as Map<String, dynamic>)['msg'] as String?;
        if (msg != null) return LdcRewardResult.error(msg);
      }
      return LdcRewardResult.error(S.current.reward_networkError(e.message ?? ''));
    } catch (e) {
      return LdcRewardResult.error(S.current.reward_unknownError(e.toString()));
    }
  }
}
