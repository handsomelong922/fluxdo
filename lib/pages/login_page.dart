import 'package:flutter/material.dart';

import '../l10n/s.dart';
import '../services/cf_challenge_service.dart';
import '../services/credential_store_service.dart';
import '../services/discourse/discourse_service.dart';
import '../services/network/cookie/boundary_sync_service.dart';
import '../services/network/cookie/cookie_jar_service.dart';
import '../services/toast_service.dart';
import '../utils/blur_config.dart';
import '../widgets/auth/login_form.dart';
import '../widgets/auth/two_factor_dialog.dart';
import '../widgets/auth/webview_login_dialog.dart';
import '../widgets/common/ambient_background.dart';
import '../widgets/common/floating_logo.dart';
import '../widgets/common/loading_spinner.dart';
import 'webview_login_page.dart';

const String _linuxDoHcaptchaSiteKey = 'a776b4ac-8c4c-441e-986a-c6ee9ed8cf08';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  String? _savedUsername;
  String? _savedPassword;
  bool _credentialsLoaded = false;

  late final AnimationController _entryController;
  final List<Animation<double>> _fade = [];
  final List<Animation<Offset>> _slide = [];

  @override
  void initState() {
    super.initState();
    _setupEntryAnimations();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  void _setupEntryAnimations() {
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    for (var i = 0; i < 5; i++) {
      final start = i * 0.12;
      final end = (start + 0.6).clamp(0.0, 1.0);
      _fade.add(
        Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(
            parent: _entryController,
            curve: Interval(start, end, curve: Curves.easeOut),
          ),
        ),
      );
      _slide.add(
        Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entryController,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          ),
        ),
      );
    }
    _entryController.forward();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final saved = await CredentialStoreService().load();
      if (!mounted) return;
      setState(() {
        _savedUsername = saved.username;
        _savedPassword = saved.password;
        _credentialsLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _credentialsLoaded = true);
    }
  }

  Future<bool> _ensureCfClearance() async {
    final jar = CookieJarService();
    var clearance = await jar.getCfClearance();
    if (clearance != null && clearance.isNotEmpty) return true;
    if (!mounted) return false;

    final ok = await CfChallengeService().showManualVerify(context, true);
    if (ok != true) return false;

    await Future<void>.delayed(const Duration(milliseconds: 1500));
    for (var i = 0; i < 3; i++) {
      await BoundarySyncService.instance.syncFromWebView(cookieNames: null);
      clearance = await jar.getCfClearance();
      if (clearance != null && clearance.isNotEmpty) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  Future<bool> _handleSubmit({
    required String identifier,
    required String password,
    required bool rememberCredentials,
  }) async {
    if (!await _ensureCfClearance()) {
      if (mounted) ToastService.showError('Cloudflare 验证未完成，请重试');
      return false;
    }
    if (!mounted) return false;

    final result = await showWebViewLoginDialog(
      context,
      siteKey: _linuxDoHcaptchaSiteKey,
      identifier: identifier,
      password: password,
      onNeedSecondFactor: (need) => showTwoFactorDialog(
        context,
        hint: need.totpEnabled ? '请输入身份验证器 App 显示的 6 位验证码' : '此账号需要二步验证',
        onUseBackupCode: () => _loginWithWebView(),
      ),
    );
    if (!mounted) return false;
    if (result == null || result.status == WebViewLoginStatus.canceled) {
      return false;
    }

    if (result.status == WebViewLoginStatus.success) {
      await DiscourseService().finalizeNativeLoginSuccess(identifier);
      if (rememberCredentials) {
        try {
          await CredentialStoreService().save(identifier, password);
        } catch (e) {
          debugPrint('[LoginPage] 保存账号失败，不影响登录: $e');
        }
      }
      if (!mounted) return true;
      ToastService.showSuccess(S.current.webviewLogin_loginSuccess);
      Navigator.of(context).pop(true);
      return true;
    }

    _showFailureToast(
      LoginFailure(
        result.loginErrorKind ?? LoginErrorKind.unknown,
        message: result.errorMessage,
      ),
    );
    return false;
  }

  void _showFailureToast(LoginFailure failure) {
    final msg = switch (failure.kind) {
      LoginErrorKind.invalidCredentials => '用户名或密码错误',
      LoginErrorKind.secondFactorRequired => failure.message ?? '二步验证失败',
      LoginErrorKind.notActivated =>
        '账号未激活，请到邮箱 ${failure.sentToEmail ?? ''} 完成激活',
      LoginErrorKind.notApproved => '账号尚未通过审核',
      LoginErrorKind.passwordExpired => '密码已过期，请用浏览器登录重设密码',
      LoginErrorKind.network => failure.message ?? '网络异常',
      LoginErrorKind.unknown => failure.message ?? '登录失败',
    };
    ToastService.showError(msg);
  }

  Future<void> _loginWithWebView([String? initialUrl]) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WebViewLoginPage(initialUrl: initialUrl),
      ),
    );
    if (result == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _clearSavedCredentials() async {
    await CredentialStoreService().clear();
    if (!mounted) return;
    setState(() {
      _savedUsername = null;
      _savedPassword = null;
    });
    ToastService.showSuccess('已清除保存的账号密码');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          const AmbientBackground(),
          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 4,
                  left: 4,
                  child: _entry(
                    0,
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: '返回',
                      style: IconButton.styleFrom(
                        backgroundColor: scheme.surface.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
                if (_credentialsLoaded && _savedUsername != null)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _entry(
                      0,
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        tooltip: '清除保存的账号',
                        style: IconButton.styleFrom(
                          backgroundColor: scheme.surface.withValues(
                            alpha: 0.3,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _clearSavedCredentials,
                      ),
                    ),
                  ),
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 32,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _entry(
                            0,
                            const Center(
                              child: FloatingLogo(size: 88, glowSize: 80),
                            ),
                          ),
                          const SizedBox(height: 28),
                          _entry(
                            1,
                            Text(
                              'Linux.do',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _entry(
                            2,
                            Text(
                              context.l10n.login_slogan,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.85,
                                ),
                                letterSpacing: 2,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          _entry(3, _buildFormCard(theme, scheme)),
                          const SizedBox(height: 24),
                          _entry(4, _buildAltLogin(context, scheme)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _entry(int index, Widget child) {
    return FadeTransition(
      opacity: _fade[index],
      child: SlideTransition(position: _slide[index], child: child),
    );
  }

  Widget _buildFormCard(ThemeData theme, ColorScheme scheme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.4 : 0.1,
            ),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: createBlurFilter(blurSigma),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: !_credentialsLoaded
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: LoadingSpinner(size: 40)),
                  )
                : LoginForm(
                    onSubmit: _handleSubmit,
                    onForgotPassword: () =>
                        _loginWithWebView('https://linux.do/password-reset'),
                    savedUsername: _savedUsername,
                    savedPassword: _savedPassword,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildAltLogin(BuildContext context, ColorScheme scheme) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _DividerWithLabel(label: '或'),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _loginWithWebView(),
          icon: const Icon(Icons.open_in_browser, size: 20),
          label: const Text('其他方式登录 (OAuth / Passkey / 注册)'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          context.l10n.login_browserHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

class _DividerWithLabel extends StatelessWidget {
  const _DividerWithLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
