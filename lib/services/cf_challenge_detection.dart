/// HTTP 挑战识别的纯逻辑。只接受明确响应标记，不把普通服务故障当作验证。
abstract final class CfChallengeDetection {
  static bool hasChallengeHeader(String? value) =>
      value?.trim().toLowerCase() == 'challenge';

  static bool isRecoverableStatus(int? status) =>
      status == 403 || status == 429 || status == 503;

  static bool isResponse({
    required int? status,
    String? mitigated,
    String? contentType,
    Object? body,
  }) {
    if (hasChallengeHeader(mitigated)) return true;
    if (!isRecoverableStatus(status)) return false;
    final type = (contentType ?? '').toLowerCase();
    if (type.isNotEmpty && !type.contains('text/html')) return false;
    return isBody(body);
  }

  static bool isBody(Object? body) {
    // JSON 帖子内容即使谈到 Cloudflare，也不是挑战 HTML。
    if (body is! String) return false;
    return body.contains('cf_chl_opt') ||
        (body.contains('challenge-platform') && body.contains('cloudflare')) ||
        (body.contains('Just a moment') &&
            (body.contains('cloudflare') || body.contains('cf-challenge')));
  }
}
