import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../cf_challenge_service.dart';
import '../../cf_challenge_logger.dart';
import '../../cf_clearance_refresh_service.dart';
import '../cookie/cookie_jar_service.dart';
import '../exceptions/api_exception.dart';

/// Cloudflare 验证拦截器
/// 处理 CF Turnstile 验证
class CfChallengeInterceptor extends Interceptor {
  CfChallengeInterceptor({
    required this.dio,
    required this.cookieJarService,
  });

  final Dio dio;
  final CookieJarService cookieJarService;

  /// 共享的 cookie 同步 Future：验证成功后只执行一次 sync
  static Future<bool>? _activeSyncFuture;

  /// 验证成功后的共享 Cookie 同步（只执行一次）
  Future<bool> _syncCookiesOnce() async {
    // 如果已有同步任务在进行，复用结果
    if (_activeSyncFuture != null) return _activeSyncFuture!;

    _activeSyncFuture = _doSync();
    try {
      return await _activeSyncFuture!;
    } finally {
      _activeSyncFuture = null;
    }
  }

  Future<bool> _doSync() async {
    await Future.delayed(const Duration(milliseconds: 1500));
    await cookieJarService.syncFromWebView();

    String? cfClearance;
    for (var i = 0; i < 3; i++) {
      cfClearance = await cookieJarService.getCfClearance();
      if (cfClearance != null && cfClearance.isNotEmpty) break;
      debugPrint('[Dio] cf_clearance not found, retry ${i + 1}/3...');
      await Future.delayed(const Duration(milliseconds: 500));
      await cookieJarService.syncFromWebView();
    }

    if (cfClearance == null || cfClearance.isEmpty) {
      CfChallengeLogger.log('[INTERCEPTOR] cf_clearance not found after sync');
      return false;
    }
    CfChallengeLogger.log('[INTERCEPTOR] cf_clearance verified: ${cfClearance.length} chars');
    return true;
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final statusCode = err.response?.statusCode;
    final data = err.response?.data;

    // 检查是否标记跳过 CF 验证（防止重试后再次触发）
    final skipCfChallenge = err.requestOptions.extra['skipCfChallenge'] == true;

    if (statusCode == 403 &&
        CfChallengeService.isCfChallenge(data) &&
        !skipCfChallenge) {
      // 备选提取 sitekey（从 403 响应体中）
      CfClearanceRefreshService().extractAndUpdateSitekey(data.toString());
      // 403 说明 cf_clearance 已失效，停止自动续期（避免与手动验证冲突）
      CfClearanceRefreshService().stop();

      final requestUrl = err.requestOptions.uri.toString();
      debugPrint('[Dio] CF Challenge detected, showing manual verify...');
      CfChallengeLogger.logInterceptorDetected(url: requestUrl, statusCode: statusCode!);
      unawaited(CfChallengeLogger.logAccessIps(url: requestUrl, context: 'interceptor'));

      final cfService = CfChallengeService();

      // 检查是否在冷却期
      if (cfService.isInCooldown) {
        debugPrint('[Dio] CF Challenge in cooldown, rejecting request');
        CfChallengeLogger.log('[INTERCEPTOR] Skipped: in cooldown');
        CfChallengeService.showGlobalMessage('安全验证失败，已进入冷却期，请稍后再试');
        return handler.reject(DioException(
          requestOptions: err.requestOptions,
          error: CfChallengeException(inCooldown: true),
          type: DioExceptionType.unknown,
        ));
      }

      // 检查请求是否标记为静默（后台验证）
      final isSilent = err.requestOptions.extra['isSilent'] == true;
      // 默认为前台强制验证，除非明确标记为静默
      final forceForeground = !isSilent;

      final result = await cfService.showManualVerify(null, forceForeground);

      if (result == true) {
        // 共享 cookie 同步（多个 403 请求只执行一次）
        final syncOk = await _syncCookiesOnce();
        if (!syncOk) {
          debugPrint('[Dio] cf_clearance not found after sync, entering cooldown');
          cfService.startCooldown();
          CfChallengeService.showGlobalMessage('验证未生效，请稍后重试');
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            error: CfChallengeException(cause: 'cf_clearance cookie 同步失败'),
            type: DioExceptionType.unknown,
          ));
        }

        // 各自重试自己的原始请求（每个请求 URL/参数不同，无法共享）
        try {
          final retryOptions = err.requestOptions;
          retryOptions.extra['skipCfChallenge'] = true;
          // 清除原始请求中残留的 cookie header，让 CookieManager 重新读取最新的 cookie
          retryOptions.headers.remove('cookie');
          retryOptions.headers.remove('Cookie');
          // 诊断：记录 CookieJar 中的 cookie 名称和 cf_clearance 状态
          final cookieHeader = await cookieJarService.getCookieHeader();
          final hasCfClearance = cookieHeader?.contains('cf_clearance=') ?? false;
          final cookieNames = cookieHeader
              ?.split('; ')
              .map((c) => c.split('=').first)
              .join(', ');
          debugPrint('[Dio] Retry cookies: ${hasCfClearance ? "✓ 包含 cf_clearance" : "⚠️ 缺少 cf_clearance"}, '
              'names=[$cookieNames], total=${cookieHeader?.length ?? 0} chars');
          final response = await dio.fetch(retryOptions);
          CfChallengeLogger.logInterceptorRetry(
            url: requestUrl,
            success: true,
            statusCode: response.statusCode,
          );
          return handler.resolve(response);
        } catch (e) {
          // 诊断：记录完整的重试失败信息
          if (e is DioException) {
            debugPrint('[Dio] Retry failed: status=${e.response?.statusCode}, '
                'type=${e.type}, url=${e.requestOptions.uri}');
            if (e.response?.statusCode == 403) {
              debugPrint('[Dio] Retry got 403 again — cf_clearance may not have been sent or already expired');
            }
          } else {
            debugPrint('[Dio] Retry failed (non-Dio): $e');
          }
          CfChallengeLogger.logInterceptorRetry(
            url: requestUrl,
            success: false,
            error: e.toString(),
          );
          // CF 验证已成功，重试失败是其他原因，传递实际错误以便排查
          if (e is DioException) {
            return handler.reject(e);
          }
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            error: e,
            type: DioExceptionType.unknown,
          ));
        }
      } else if (result == null) {
        // null 可能是冷却期内，也可能是无 context
        if (cfService.isInCooldown) {
          CfChallengeService.showGlobalMessage('安全验证失败，已进入冷却期，请稍后再试');
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            error: CfChallengeException(inCooldown: true),
            type: DioExceptionType.unknown,
          ));
        }
        // 无 context（应用刚启动，context 还没设置好）
        debugPrint(
            '[Dio] CF Challenge: no context available, cannot show verify page');
        CfChallengeLogger.log('[INTERCEPTOR] No context available');
        CfChallengeService.showGlobalMessage('无法打开验证页面，请稍后重试');
        return handler.reject(DioException(
          requestOptions: err.requestOptions,
          error: CfChallengeException(cause: '无法获取 context，验证页面未展示'),
          type: DioExceptionType.unknown,
        ));
      } else {
        // result == false：用户取消或验证失败
        CfChallengeLogger.log('[INTERCEPTOR] User cancelled or verify failed');
        CfChallengeService.showGlobalMessage('验证未完成，请重试');
        return handler.reject(DioException(
          requestOptions: err.requestOptions,
          error: CfChallengeException(userCancelled: true),
          type: DioExceptionType.unknown,
        ));
      }
    }

    handler.next(err);
  }
}
