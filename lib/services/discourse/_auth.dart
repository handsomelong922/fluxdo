part of 'discourse_service.dart';

/// 认证相关
mixin _AuthMixin on _DiscourseServiceBase {
  /// 正在验证 session 是否真正失效（防止并发验证）
  bool _isVerifyingSession = false;

  /// 初始化拦截器
  void _initInterceptors() {
    // 设置 PreloadedDataService 的登录失效回调
    PreloadedDataService().setAuthInvalidCallback(() {
      _handleAuthInvalid(
        S.current.auth_loginExpiredRelogin,
        source: 'preloaded_data',
        triggerInfo: '有 token 但没有 currentUser，WebView 验证确认已登出',
      );
    });

    // 添加业务特定拦截器
    _dio.interceptors.insert(0, InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (!_credentialsLoaded) {
          await _loadStoredCredentials();
          _credentialsLoaded = true;
        }

        if (_tToken != null && _tToken!.isNotEmpty) {
          options.headers['Discourse-Logged-In'] = 'true';
          options.headers['Discourse-Present'] = 'true';
        }

        debugPrint('[DIO] ${options.method} ${options.uri}');
        handler.next(options);
      },
      onResponse: (response, handler) async {
        final skipAuthCheck = response.requestOptions.extra['skipAuthCheck'] == true;

        final loggedOut = response.headers.value('discourse-logged-out');
        if (!skipAuthCheck && loggedOut != null && loggedOut.isNotEmpty && !_isLoggingOut) {
          await _onDiscourseLoggedOut(
            source: 'response_header',
            triggerInfo: '${response.requestOptions.method} ${response.requestOptions.uri} → ${response.statusCode}',
            requestOptions: response.requestOptions,
            statusCode: response.statusCode,
            responseHeaders: response.headers.map,
          );
          return handler.next(response);
        }

        final tToken = await _cookieJar.getTToken();
        if (tToken != null && tToken.isNotEmpty) {
          _tToken = tToken;
        }

        final username = response.headers.value('x-discourse-username');
        if (username != null && username.isNotEmpty && username != _username) {
          _username = username;
          _storage.write(key: DiscourseService._usernameKey, value: username);
        }

        debugPrint('[DIO] ${response.statusCode} ${response.requestOptions.uri}');
        handler.next(response);
      },
      onError: (error, handler) async {
        final skipAuthCheck = error.requestOptions.extra['skipAuthCheck'] == true;
        final data = error.response?.data;
        debugPrint('[DIO] Error: ${error.response?.statusCode}');

        // BAD CSRF 处理：清空 token → 刷新 → 重试原请求
        // 用 extra 标记防止无限循环，只重试一次
        if (error.response?.statusCode == 403 &&
            _isBadCsrfResponse(data) &&
            error.requestOptions.extra['_csrfRetried'] != true) {
          debugPrint('[DIO] BAD CSRF detected, refreshing csrfToken and retrying');
          _cookieSync.clearCsrfToken();
          await _cookieSync.updateCsrfToken();
          // 用新 token 重试原请求
          final options = error.requestOptions;
          options.extra['_csrfRetried'] = true;
          final csrf = _cookieSync.csrfToken;
          options.headers['X-CSRF-Token'] = (csrf == null || csrf.isEmpty) ? 'undefined' : csrf;
          try {
            final response = await _dio.fetch(options);
            return handler.resolve(response);
          } on DioException catch (e) {
            return handler.next(e);
          }
        }

        final loggedOut = error.response?.headers.value('discourse-logged-out');
        if (!skipAuthCheck && loggedOut != null && loggedOut.isNotEmpty && !_isLoggingOut) {
          await _onDiscourseLoggedOut(
            source: 'error_response_header',
            triggerInfo: '${error.requestOptions.method} ${error.requestOptions.uri} → ${error.response?.statusCode}',
            requestOptions: error.requestOptions,
            statusCode: error.response?.statusCode,
            responseHeaders: error.response?.headers.map,
          );
          return handler.next(error);
        }

        if (!skipAuthCheck && data is Map && data['error_type'] == 'not_logged_in') {
          final jarTToken = await _cookieJar.getTToken();
          await AuthLogService().logAuthInvalid(
            source: 'error_response',
            reason: data['error_type']?.toString() ?? 'not_logged_in',
            extra: {
              'method': error.requestOptions.method,
              'url': error.requestOptions.uri.toString(),
              'statusCode': error.response?.statusCode,
              'errors': data['errors'],
              'jarHasToken': jarTToken != null && jarTToken.isNotEmpty,
              'jarTokenLength': jarTToken?.length,
              'memHasToken': _tToken != null && _tToken!.isNotEmpty,
            },
          );
          final message = (data['errors'] as List?)?.first?.toString() ?? S.current.auth_loginExpiredRelogin;
          await _handleAuthInvalid(
            message,
            source: 'error_response_body',
            triggerInfo: '${error.requestOptions.method} ${error.requestOptions.uri} → ${error.response?.statusCode}, error_type=${data['error_type']}',
          );
        }

        handler.next(error);
      },
    ));
  }

  /// 收到 discourse-logged-out header 时的处理
  ///
  /// 不立即 logout（不可逆），而是先验证 session 是否真的失效。
  /// Discourse 官方 Web 前端收到此 header 也只是弹提示，并不强制登出。
  ///
  /// 验证方式：通过 PreloadedDataService 请求首页 HTML，
  /// 检查 data-preloaded 中是否包含 currentUser。
  /// 该请求共享同一个 CookieJar，会携带当前 _t。
  /// 如果服务器真的不认 _t，返回的 HTML 不含 currentUser → 真正登出。
  /// 如果服务器认可 _t（瞬态误判），返回的 HTML 包含 currentUser → 忽略。
  Future<void> _onDiscourseLoggedOut({
    required String source,
    required String triggerInfo,
    required RequestOptions requestOptions,
    int? statusCode,
    Map<String, List<String>>? responseHeaders,
  }) async {
    // 已在验证中或已在登出中，跳过
    if (_isVerifyingSession || _isLoggingOut) return;

    final jarTToken = await _cookieJar.getTToken();

    // _t 已经不存在 → 确实需要登出（可能已被 Set-Cookie 删除）
    if (jarTToken == null || jarTToken.isEmpty) {
      debugPrint('[Auth] discourse-logged-out: _t 已不存在，直接登出');
      await AuthLogService().logAuthInvalid(
        source: source,
        reason: 'discourse-logged-out',
        extra: {
          'method': requestOptions.method,
          'url': requestOptions.uri.toString(),
          'statusCode': statusCode,
          'jarHasToken': false,
          'memHasToken': _tToken != null && _tToken!.isNotEmpty,
          'verified': false,
        },
      );
      await _handleAuthInvalid(
        S.current.auth_loginExpiredRelogin,
        source: source,
        triggerInfo: triggerInfo,
      );
      return;
    }

    // _t 存在 → 验证 session 是否真的失效
    _isVerifyingSession = true;
    debugPrint('[Auth] discourse-logged-out: 开始验证 session (trigger: $triggerInfo)');

    try {
      // 通过 PreloadedDataService 验证：它会请求首页 HTML 并解析 currentUser
      await PreloadedDataService().refresh();
      final currentUser = PreloadedDataService().currentUserSync;

      if (currentUser != null) {
        // session 有效 → 忽略 discourse-logged-out（瞬态误判）
        debugPrint('[Auth] discourse-logged-out 验证通过: session 仍然有效，忽略');
        LogWriter.instance.write({
          'timestamp': DateTime.now().toIso8601String(),
          'level': 'info',
          'type': 'lifecycle',
          'event': 'logout_prevented',
          'message': 'discourse-logged-out 验证后 session 仍有效，忽略',
          'source': source,
          'trigger': triggerInfo,
          'jarTokenLen': jarTToken.length,
        });
      } else {
        // session 确实失效 → 登出
        debugPrint('[Auth] discourse-logged-out 验证失败: session 已失效');
        await AuthLogService().logAuthInvalid(
          source: source,
          reason: 'discourse-logged-out (verified)',
          extra: {
            'method': requestOptions.method,
            'url': requestOptions.uri.toString(),
            'statusCode': statusCode,
            'jarHasToken': true,
            'jarTokenLen': jarTToken.length,
            'memHasToken': _tToken != null && _tToken!.isNotEmpty,
            'verified': true,
          },
        );
        await _handleAuthInvalid(
          S.current.auth_loginExpiredRelogin,
          source: source,
          triggerInfo: '$triggerInfo (verified)',
        );
      }
    } catch (e) {
      // 验证请求本身失败（网络错误等）→ 不要因为验证失败就登出
      debugPrint('[Auth] discourse-logged-out 验证异常: $e，暂不处理');
      LogWriter.instance.write({
        'timestamp': DateTime.now().toIso8601String(),
        'level': 'warning',
        'type': 'lifecycle',
        'event': 'logout_verify_failed',
        'message': 'discourse-logged-out 验证请求失败，暂不登出',
        'source': source,
        'trigger': triggerInfo,
        'error': e.toString(),
      });
    } finally {
      _isVerifyingSession = false;
    }
  }

  /// 判断响应是否为 BAD CSRF
  /// Discourse 返回 403 + '["BAD CSRF"]' 表示 CSRF token 校验失败
  bool _isBadCsrfResponse(dynamic data) {
    if (data is String) return data == '["BAD CSRF"]';
    if (data is List) return data.length == 1 && data.first == 'BAD CSRF';
    return false;
  }

  /// 设置导航 context
  void setNavigatorContext(BuildContext context) {
    _cfChallenge.setContext(context);
  }

  Future<void> _handleAuthInvalid(
    String message, {
    String? source,
    String? triggerInfo,
  }) async {
    if (_isLoggingOut) return;
    _isLoggingOut = true;

    // ===== 第一步：立即切断所有在途请求 =====
    // 先于 logout 执行，防止用户在失效状态下继续操作产生更多 403
    AuthSession().advance();

    // 收集 _t cookie 诊断信息（不含实际值，仅状态）
    final jarTToken = await _cookieJar.getTToken();
    final csrfToken = _cookieSync.csrfToken;

    // 记录被动退出日志（含触发来源，方便排查）
    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'warning',
      'type': 'lifecycle',
      'event': 'logout_passive',
      'message': '登录失效被动退出',
      'reason': message,
      if (source != null) 'source': source,
      if (triggerInfo != null) 'trigger': triggerInfo,
      // _t cookie 诊断（仅记录有无和长度，不记录实际值）
      'memHasToken': _tToken != null && _tToken!.isNotEmpty,
      'jarHasToken': jarTToken != null && jarTToken.isNotEmpty,
      'jarTokenLen': jarTToken?.length,
      'hasCsrf': csrfToken != null && csrfToken.isNotEmpty,
    });

    await logout(callApi: false, refreshPreload: true);
    _isLoggingOut = false;
    _authErrorController.add(message);
  }

  /// 检查是否已登录
  Future<bool> isLoggedIn() async {
    final tToken = await _cookieJar.getTToken();
    if (tToken == null || tToken.isEmpty) return false;
    _tToken = tToken;
    _username = await _storage.read(key: DiscourseService._usernameKey);
    return true;
  }

  /// 仅设置 token，不触发状态广播（登录流程中先设置 token，等数据就绪后再广播）
  void setToken(String tToken) {
    _tToken = tToken;
    _credentialsLoaded = false;
  }

  /// 登录成功后通知监听者（应在预加载数据就绪后调用）
  /// Cookie 写入由 syncFromWebView() 统一处理。
  void onLoginSuccess(String tToken) {
    _tToken = tToken;
    _credentialsLoaded = false;
    _authStateController.add(null);
  }

  /// 保存用户名
  Future<void> saveUsername(String username) async {
    _username = username;
    await _storage.write(key: DiscourseService._usernameKey, value: username);
  }

  /// 登出
  Future<void> logout({bool callApi = true, bool refreshPreload = true}) async {
    // ===== 第一步：切断所有旧请求 =====
    AuthSession().advance();

    // ===== 第二步：主动停止后台 Service =====
    MessageBusService().stopAll();
    CfClearanceRefreshService().stop();

    // ===== 第三步：调用登出 API（可选，用新的 generation） =====
    if (callApi) {
      final usernameForLogout = _username ?? await _storage.read(key: DiscourseService._usernameKey);
      try {
        if (usernameForLogout != null && usernameForLogout.isNotEmpty) {
          await _dio.delete('/session/$usernameForLogout');
        }
      } catch (e) {
        debugPrint('[DiscourseService] Logout API failed: $e');
      }
    }

    // ===== 第四步：清除内存状态 =====
    _tToken = null;
    _username = null;
    _cachedUserSummary = null;
    _cachedUserSummaryUsername = null;
    _userSummaryCacheTime = null;
    await _storage.delete(key: DiscourseService._usernameKey);
    _credentialsLoaded = false;

    // ===== 第五步：清除 Cookie（保留 cf_clearance）=====
    await _cookieSync.reset();
    final cfClearanceCookie = await _cookieJar.getCfClearanceCookie();
    await _cookieJar.clearAll();
    if (cfClearanceCookie != null) {
      await _cookieJar.restoreCfClearance(cfClearanceCookie);
    }

    // ===== 第六步：刷新预加载数据（确保新状态就绪后再广播）=====
    PreloadedDataService().reset();
    if (refreshPreload) {
      await PreloadedDataService().refresh();
    }

    // ===== 第七步：广播状态变更（此时一切已就绪）=====
    currentUserNotifier.value = null;
    _authStateController.add(null);
  }
}
