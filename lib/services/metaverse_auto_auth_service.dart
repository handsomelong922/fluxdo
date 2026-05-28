import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/cdk_providers.dart';
import '../providers/core_providers.dart';
import '../providers/ldc_providers.dart';
import '../providers/theme_provider.dart';
import 'cdk_oauth_service.dart';
import 'ldc_oauth_service.dart';
import 'network/exceptions/oauth_exception.dart';

/// 元宇宙服务启动自检与静默授权。
///
/// 只走可被 Dio 自动完成的 OAuth approve 流程；如果站点要求 WebView
/// 人机验证或额外交互，则静默失败，保留手动入口，不打断用户。
class MetaverseAutoAuthService {
  MetaverseAutoAuthService._();

  static const String _ldcEnabledKey = 'ldc_enabled';
  static const String _cdkEnabledKey = 'cdk_enabled';
  static bool _isRunning = false;

  static Future<void> ensureEnabled(WidgetRef ref) async {
    if (_isRunning) return;
    _isRunning = true;

    final prefs = ref.read(sharedPreferencesProvider);
    final currentUser = ref.read(currentUserProvider).value;
    final ldcNotifier = ref.read(ldcUserInfoProvider.notifier);
    final cdkNotifier = ref.read(cdkUserInfoProvider.notifier);

    try {
      await _ensureLdc(
        prefs: prefs,
        notifier: ldcNotifier,
        gamificationScore: currentUser?.gamificationScore,
      );
      await _ensureCdk(prefs: prefs, notifier: cdkNotifier);
    } finally {
      _isRunning = false;
    }
  }

  static Future<void> _ensureLdc({
    required SharedPreferences prefs,
    required LdcUserInfoNotifier notifier,
    required int? gamificationScore,
  }) async {
    final service = LdcOAuthService();
    final enabled = prefs.getBool(_ldcEnabledKey) ?? false;

    try {
      if (enabled) {
        await service.getUserInfo(gamificationScore: gamificationScore);
        await notifier.refresh();
        return;
      }

      final authorized = await service.authorizeSilently();
      if (!authorized) return;

      await prefs.setBool(_ldcEnabledKey, true);
      await notifier.refresh();
    } on OAuthExpiredException catch (_) {
      await _trySilentLdcReauth(prefs, notifier);
    } catch (e) {
      debugPrint('[MetaverseAutoAuth] LDC 静默授权失败: $e');
    }
  }

  static Future<void> _trySilentLdcReauth(
    SharedPreferences prefs,
    LdcUserInfoNotifier notifier,
  ) async {
    try {
      final authorized = await LdcOAuthService().authorizeSilently();
      if (!authorized) return;
      await prefs.setBool(_ldcEnabledKey, true);
      await notifier.refresh();
    } catch (e) {
      debugPrint('[MetaverseAutoAuth] LDC 静默重新授权失败: $e');
    }
  }

  static Future<void> _ensureCdk({
    required SharedPreferences prefs,
    required CdkUserInfoNotifier notifier,
  }) async {
    final service = CdkOAuthService();
    final enabled = prefs.getBool(_cdkEnabledKey) ?? false;

    try {
      if (enabled) {
        await service.getUserInfo();
        await notifier.refresh();
        return;
      }

      final authorized = await service.authorizeSilently();
      if (!authorized) return;

      await prefs.setBool(_cdkEnabledKey, true);
      await notifier.refresh();
    } on OAuthExpiredException catch (_) {
      await _trySilentCdkReauth(prefs, notifier);
    } catch (e) {
      debugPrint('[MetaverseAutoAuth] CDK 静默授权失败: $e');
    }
  }

  static Future<void> _trySilentCdkReauth(
    SharedPreferences prefs,
    CdkUserInfoNotifier notifier,
  ) async {
    try {
      final authorized = await CdkOAuthService().authorizeSilently();
      if (!authorized) return;
      await prefs.setBool(_cdkEnabledKey, true);
      await notifier.refresh();
    } catch (e) {
      debugPrint('[MetaverseAutoAuth] CDK 静默重新授权失败: $e');
    }
  }
}
