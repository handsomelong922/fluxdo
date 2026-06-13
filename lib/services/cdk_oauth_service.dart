import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'network/discourse_dio.dart';
import 'network/exceptions/oauth_exception.dart';
import '../pages/oauth_webview_page.dart';
import '../l10n/s.dart';
import 'oauth_flow_helper.dart';
import '../models/cdk_user_info.dart';

class CdkOAuthService {
  static const String baseUrl = 'https://cdk.linux.do';

  late final Dio _dio;

  CdkOAuthService() {
    _dio = DiscourseDio.create();
  }

  Future<String> getAuthUrl() async {
    final response = await _dio.get(
      '$baseUrl/api/v1/oauth/login',
      options: Options(extra: {'skipCsrf': true}),
    );
    return response.data['data'] as String;
  }

  Future<void> callback(String code, String state) async {
    await _dio.post(
      '$baseUrl/api/v1/oauth/callback',
      data: {'code': code, 'state': state},
      options: Options(
        headers: {'X-Requested-With': 'XMLHttpRequest'},
        extra: {'skipCsrf': true},
      ),
    );
  }

  Future<void> logout() async {
    await _dio.get(
      '$baseUrl/api/v1/oauth/logout',
      options: Options(extra: {'skipCsrf': true}),
    );
  }

  Future<CdkUserInfo?> getUserInfo() async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/v1/oauth/user-info',
        options: Options(extra: {'skipCsrf': true, 'showErrorToast': false}),
      );
      final cdkData = response.data['data'];
      return CdkUserInfo.fromJson(cdkData);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 401 || statusCode == 403) {
        throw OAuthExpiredException(serviceName: 'CDK', statusCode: statusCode);
      }
      rethrow;
    }
  }

  Future<bool> reauthorize(BuildContext context) async {
    try {
      await logout();
    } catch (_) {
      // 忽略登出错误，不阻塞后续重新授权。
    }
    await OAuthFlowHelper.humanGap(minMs: 1000, maxMs: 1800);
    if (!context.mounted) return false;
    return authorize(context);
  }

  Future<bool> reauthorizeSilently() async {
    try {
      await logout();
    } catch (_) {
      // 忽略登出错误，不阻塞后续静默授权。
    }
    await OAuthFlowHelper.humanGap(minMs: 600, maxMs: 1200);
    return authorizeSilently();
  }

  Future<bool> authorize(BuildContext context) async {
    final authUrl = await _loadAuthUrl();
    await OAuthFlowHelper.humanGap(minMs: 800, maxMs: 1500);
    final response = await _loadAuthPage(authUrl);

    if (await _tryCallbackFromLocation(response.headers.value('location'))) {
      return true;
    }

    final approveLink = _extractApproveLink(response.data);

    if (!context.mounted) return false;
    if (approveLink == null) {
      return _authorizeWithWebView(context, authUrl);
    }

    try {
      await _approveAndCallback(approveLink);
      return true;
    } on _OAuthNeedsWebViewFallback {
      if (!context.mounted) return false;
      return _authorizeWithWebView(context, authUrl);
    }
  }

  Future<bool> authorizeSilently() async {
    try {
      final authUrl = await _loadAuthUrl();
      await OAuthFlowHelper.humanGap(minMs: 400, maxMs: 900);
      final response = await _loadAuthPage(authUrl);

      if (await _tryCallbackFromLocation(response.headers.value('location'))) {
        return true;
      }

      final approveLink = _extractApproveLink(response.data);
      if (approveLink == null) {
        return false;
      }

      await _approveAndCallback(approveLink);
      return true;
    } on _OAuthNeedsWebViewFallback {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _authorizeWithWebView(
    BuildContext context,
    String authUrl,
  ) async {
    final callbackResult = await Navigator.of(context).push<OAuthWebViewResult>(
      MaterialPageRoute(
        builder: (_) => OAuthWebViewPage(
          initialUrl: authUrl,
          callbackBaseUrl: baseUrl,
          title: context.l10n.auth_cdkConfirmTitle,
        ),
      ),
    );
    if (callbackResult == null) {
      return false;
    }
    await OAuthFlowHelper.humanGap(minMs: 400, maxMs: 900);
    await callback(callbackResult.code, callbackResult.state);
    return true;
  }

  Future<String> _loadAuthUrl() async {
    final String authUrl;
    try {
      authUrl = await getAuthUrl();
    } on DioException {
      throw Exception(S.current.oauth_getAuthUrlFailed);
    }
    return authUrl;
  }

  Future<Response<dynamic>> _loadAuthPage(String authUrl) async {
    final Response response;
    try {
      response = await _dio.get(
        authUrl,
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
          extra: {'skipCsrf': true, 'allowRedirectSetCookie': true},
        ),
      );
    } on DioException {
      throw Exception(S.current.oauth_networkError);
    }
    return response;
  }

  String? _extractApproveLink(Object? html) {
    final document = html_parser.parse(html?.toString() ?? '');
    return document
        .querySelector('a[href*="/oauth2/approve/"]')
        ?.attributes['href'];
  }

  Future<bool> _tryCallbackFromLocation(String? location) async {
    if (location == null || location.isEmpty) {
      return false;
    }
    final uri = Uri.tryParse(location);
    if (uri == null) {
      return false;
    }
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    if (code == null || state == null) {
      return false;
    }
    await OAuthFlowHelper.humanGap(minMs: 400, maxMs: 900);
    await callback(code, state);
    return true;
  }

  Future<void> _approveAndCallback(String approveLink) async {
    final approveUri = Uri.parse(
      'https://connect.linux.do',
    ).resolve(approveLink);
    await OAuthFlowHelper.humanGap(minMs: 600, maxMs: 1200);
    final approveResponse = await _dio.get(
      approveUri.toString(),
      options: Options(
        followRedirects: false,
        validateStatus: (status) => status != null && status < 500,
        extra: {
          'skipCsrf': true,
          'skipRedirect': true,
          'allowRedirectSetCookie': true,
        },
      ),
    );

    final location = approveResponse.headers.value('location');
    if (location == null) {
      throw const _OAuthNeedsWebViewFallback();
    }

    final uri = Uri.parse(location);
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];

    if (code == null || state == null) {
      throw const _OAuthNeedsWebViewFallback();
    }

    await OAuthFlowHelper.humanGap(minMs: 400, maxMs: 900);
    await callback(code, state);
  }
}

class _OAuthNeedsWebViewFallback implements Exception {
  const _OAuthNeedsWebViewFallback();
}
