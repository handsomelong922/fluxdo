part of 'discourse_service.dart';

/// 原生登录/登录对话框共享逻辑。
///
/// 真正的 hCaptcha + session 请求由 WebView 内同源 JS 发出，这里只负责解析
/// `/session.json` 的响应和复用当前分支登录收口流程。
mixin _LoginMixin on _DiscourseServiceBase, _AuthMixin {
  LoginResult parseSessionJsonBody(int status, String body) {
    Map<String, dynamic>? map;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        map = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      map = null;
    }

    if (map == null) {
      return LoginResult.error(
        LoginErrorKind.unknown,
        message: 'Discourse 返回非 JSON: HTTP $status',
      );
    }

    final reason = map['reason']?.toString();
    if (reason != null) return _parseLoginError(reason, map);
    if (map['error'] != null && map['user'] == null) {
      return LoginResult.error(
        LoginErrorKind.unknown,
        message: map['error']?.toString(),
      );
    }
    return const LoginResult.success();
  }

  LoginResult _parseLoginError(String reason, Map<String, dynamic> body) {
    switch (reason) {
      case 'invalid_second_factor':
      case 'second_factor':
        return LoginResult.error(
          LoginErrorKind.secondFactorRequired,
          message: body['error']?.toString(),
          totpEnabled: body['totp_enabled'] == true,
          securityKeyEnabled: body['security_key_enabled'] == true,
          backupEnabled: body['backup_enabled'] == true,
        );
      case 'invalid_credentials':
        return LoginResult.error(
          LoginErrorKind.invalidCredentials,
          message: body['error']?.toString(),
        );
      case 'not_activated':
        return LoginResult.error(
          LoginErrorKind.notActivated,
          message: body['error']?.toString(),
          sentToEmail: body['sent_to_email']?.toString(),
          currentEmail: body['current_email']?.toString(),
        );
      case 'not_approved':
        return LoginResult.error(
          LoginErrorKind.notApproved,
          message: body['error']?.toString(),
        );
      case 'expired':
        return LoginResult.error(
          LoginErrorKind.passwordExpired,
          message: body['error']?.toString(),
        );
      default:
        return LoginResult.error(
          LoginErrorKind.unknown,
          message: body['error']?.toString() ?? 'reason=$reason',
        );
    }
  }

  Future<void> finalizeNativeLoginSuccess(String identifier) async {
    AuthSession().advance();

    final token = await _cookieJar.getTToken() ?? '';
    if (token.isEmpty) {
      debugPrint('[DiscourseLogin] 登录成功但 CookieJar 未读到 _t');
    }

    await saveUsername(identifier);
    if (token.isNotEmpty) setToken(token);

    var loginReadyNotified = false;
    try {
      await LoginReadyCoordinator(
            hydrateFromHtml: PreloadedDataService().hydrateFromHtml,
            refreshPreloadedData: PreloadedDataService().refresh,
            notifyLoginReady: (t) {
              loginReadyNotified = true;
              onLoginSuccess(t);
            },
          )
          .finalize(token: token, pageHtml: null)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[DiscourseLogin] 登录收口预加载失败/超时: $e');
    } finally {
      if (!loginReadyNotified) onLoginSuccess(token);
    }
  }
}

enum LoginErrorKind {
  invalidCredentials,
  secondFactorRequired,
  notActivated,
  notApproved,
  passwordExpired,
  network,
  unknown,
}

sealed class LoginResult {
  const LoginResult();

  const factory LoginResult.success() = LoginSuccess;

  const factory LoginResult.error(
    LoginErrorKind kind, {
    String? message,
    bool totpEnabled,
    bool securityKeyEnabled,
    bool backupEnabled,
    String? sentToEmail,
    String? currentEmail,
  }) = LoginFailure;
}

class LoginSuccess extends LoginResult {
  const LoginSuccess();
}

class LoginFailure extends LoginResult {
  const LoginFailure(
    this.kind, {
    this.message,
    this.totpEnabled = false,
    this.securityKeyEnabled = false,
    this.backupEnabled = false,
    this.sentToEmail,
    this.currentEmail,
  });

  final LoginErrorKind kind;
  final String? message;
  final bool totpEnabled;
  final bool securityKeyEnabled;
  final bool backupEnabled;
  final String? sentToEmail;
  final String? currentEmail;
}
