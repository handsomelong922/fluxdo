import 'dart:convert';
import 'dart:io' as io;
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../constants.dart';
import '../../cf_challenge_logger.dart';
import '../../windows_webview_environment_service.dart';

/// Cookie 值编解码工具
/// Dart 的 io.Cookie 严格遵循 RFC 6265，禁止值中包含双引号、逗号等字符，
/// 但浏览器允许这些字符（如 g_state 的 JSON 值）。
/// 对不合规的值进行 URL 编码后加前缀存储，在所有出口处解码还原。
class CookieValueCodec {
  static const _prefix = '~enc~';

  /// 编码不合规的 cookie 值
  static String encode(String value) => '$_prefix${Uri.encodeComponent(value)}';

  /// 解码还原浏览器原始值；未编码的值原样返回
  static String decode(String value) {
    if (value.startsWith(_prefix)) {
      return Uri.decodeComponent(value.substring(_prefix.length));
    }
    return value;
  }
}

/// 统一的 Cookie 管理服务
/// 使用 cookie_jar 库管理 Cookie，支持持久化和 WebView 同步
class CookieJarService {
  static final CookieJarService _instance = CookieJarService._internal();
  factory CookieJarService() => _instance;
  CookieJarService._internal();

  CookieJar? _cookieJar;
  bool _initialized = false;
  CookieManager get _webViewCookieManager =>
      WindowsWebViewEnvironmentService.instance.cookieManager;

  /// Apple 平台 platform channel，用于将 cookie 写入 HTTPCookieStorage.shared。
  /// WKWebView 的 sharedCookiesEnabled 在创建时从 HTTPCookieStorage.shared 读取 cookie，
  /// 比 WKHTTPCookieStore 的跨进程异步同步更可靠。
  static const _nativeCookieChannel = MethodChannel(
    'com.fluxdo/cookie_storage',
  );

  /// 获取 CookieJar 实例（用于 Dio CookieManager）
  CookieJar get cookieJar {
    if (_cookieJar == null) {
      throw StateError(
        'CookieJarService not initialized. Call initialize() first.',
      );
    }
    return _cookieJar!;
  }

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// 初始化 CookieJar（应用启动时调用）
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final cookiePath = path.join(directory.path, '.cookies');

      final cookieDir = io.Directory(cookiePath);
      if (!await cookieDir.exists()) {
        await cookieDir.create(recursive: true);
      }

      _cookieJar = PersistCookieJar(
        ignoreExpires: false,
        storage: FileStorage(cookiePath),
      );

      _initialized = true;
      debugPrint('[CookieJar] Initialized with path: $cookiePath');

      await _migrateCookieStorage();
    } catch (e) {
      debugPrint(
        '[CookieJar] Failed to create persistent storage, using memory: $e',
      );
      _cookieJar = CookieJar();
      _initialized = true;
    }
  }

  static const _migrationKey = 'cookie_domain_migration_v2';

  /// 一次性迁移（v2）：读出所有 cookie，按 name+path 去重
  /// （优先保留 domain cookie），清空后重新存入，
  /// 消除旧版本 hostCookies / domainCookies 的重复冲突。
  Future<void> _migrateCookieStorage() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migrationKey) == true) return;

    debugPrint('[CookieJar] Migrating cookie storage (v2)...');
    final jar = _cookieJar!;
    final baseHost = Uri.parse(AppConstants.baseUrl).host;
    final hosts = await _getRelatedHosts(baseHost);

    // 按 host 读出所有 cookie
    final collected = <Uri, List<io.Cookie>>{};
    for (final host in hosts) {
      final hostUri = Uri.parse('https://$host');
      final cookies = await jar.loadForRequest(hostUri);
      if (cookies.isNotEmpty) {
        collected[hostUri] = cookies;
      }
    }

    // 清空
    await jar.deleteAll();

    // 去重后重新存入：同 name+path 下优先保留 domain cookie
    for (final entry in collected.entries) {
      final sorted = [...entry.value]
        ..sort((a, b) {
          // domain cookie 排前面
          if (a.domain != null && b.domain == null) return -1;
          if (a.domain == null && b.domain != null) return 1;
          return 0;
        });
      final seen = <String>{};
      final deduped = <io.Cookie>[];
      for (final cookie in sorted) {
        if (seen.add('${cookie.name}|${cookie.path}')) {
          deduped.add(cookie);
        }
      }
      await jar.saveFromResponse(entry.key, deduped);
    }

    await prefs.setBool(_migrationKey, true);
    // 清除旧版迁移标记
    await prefs.remove('cookie_domain_migration_v1');
    debugPrint('[CookieJar] Migration v2 complete');
  }

  // ---------------------------------------------------------------------------
  // WebView ↔ CookieJar 同步
  // ---------------------------------------------------------------------------

  /// 从 WebView 同步 Cookie 到 CookieJar
  Future<void> syncFromWebView({
    String? currentUrl,
    InAppWebViewController? controller,
  }) async {
    if (!_initialized) await initialize();

    try {
      final baseUri = Uri.parse(AppConstants.baseUrl);
      final extraHosts = <String>{};
      final currentHost = Uri.tryParse(
        currentUrl ?? '',
      )?.host.trim().toLowerCase();
      if (currentHost != null &&
          currentHost.isNotEmpty &&
          (currentHost == baseUri.host ||
              currentHost.endsWith('.${baseUri.host}'))) {
        extraHosts.add(currentHost);
      }
      // Windows + controller 可用时，通过页面 controller 的 CDP 读取
      // （CookieManager 通过 environment 内部 WebView 读取，domain 前导点可能丢失）
      if (io.Platform.isWindows && controller != null) {
        await _syncFromWebViewViaController(
          controller,
          baseUri: baseUri,
          currentUrl: currentUrl,
          extraHosts: extraHosts,
        );
        return;
      }

      final webViewCookies = await _collectWebViewCookies(
        baseUri.host,
        extraHosts: extraHosts,
      );

      if (CfChallengeLogger.isEnabled) {
        CfChallengeLogger.logCookieSync(
          direction: 'WebView -> CookieJar',
          cookies: webViewCookies.values.map((snapshot) {
            final wc = snapshot.cookie;
            return CookieLogEntry(
              name: wc.name,
              domain: wc.domain,
              path: wc.path,
              expires: _parseWebViewCookieExpires(wc.expiresDate),
              valueLength: wc.value.length,
            );
          }).toList(),
        );
      }

      if (webViewCookies.isEmpty) {
        if (io.Platform.isWindows) {
          debugPrint(
            '[CookieJar][Windows] syncFromWebView 未读取到任何 Cookie: '
            'userDataFolder='
            '${WindowsWebViewEnvironmentService.instance.userDataFolder ?? "<default>"}',
          );
        }
        return;
      }

      // 按 URI 分桶、按 name+path+domain 去重
      final bucketedCookies = <Uri, Map<String, io.Cookie>>{};

      for (final snapshot in webViewCookies.values) {
        final wc = snapshot.cookie;
        final rawDomain = wc.domain?.trim();
        final normalizedDomain = _normalizeWebViewCookieDomain(rawDomain);
        final shouldPersistAsDomainCookie = _shouldPersistWebViewDomainCookie(
          rawDomain: rawDomain,
          normalizedDomain: normalizedDomain,
          sourceHosts: snapshot.sourceHosts,
        );
        String? domainAttr;
        var hostForUri = snapshot.primaryHost;

        if (normalizedDomain != null) {
          hostForUri = normalizedDomain;
          if (shouldPersistAsDomainCookie) {
            domainAttr = '.$normalizedDomain';
          }
        }

        // Dart Cookie 构造函数严格遵循 RFC 6265，对不合规值使用编码存储
        io.Cookie cookie;
        try {
          cookie = io.Cookie(wc.name, wc.value)
            ..path = wc.path ?? '/'
            ..secure = wc.isSecure ?? false
            ..httpOnly = wc.isHttpOnly ?? false;
        } catch (_) {
          cookie = io.Cookie(wc.name, CookieValueCodec.encode(wc.value))
            ..path = wc.path ?? '/'
            ..secure = wc.isSecure ?? false
            ..httpOnly = wc.isHttpOnly ?? false;
        }

        if (domainAttr != null) {
          cookie.domain = domainAttr;
        }
        final expires = _parseWebViewCookieExpires(wc.expiresDate);
        if (expires != null) {
          cookie.expires = expires;
        }

        // 跳过已过期的 cookie：写入 CookieJar 会覆盖同名有效 cookie 后被自动移除
        if (cookie.expires != null &&
            cookie.expires!.isBefore(DateTime.now())) {
          debugPrint(
            '[CookieJar] syncFromWebView: 跳过已过期 cookie ${cookie.name}',
          );
          continue;
        }

        // 跳过空值的关键 cookie：防止覆盖 CookieJar 中的有效值
        if (cookie.value.isEmpty && _isCriticalCookie(cookie.name)) {
          debugPrint(
            '[CookieJar] syncFromWebView: 跳过空值关键 cookie ${cookie.name}',
          );
          continue;
        }

        final bucketUri = Uri(scheme: baseUri.scheme, host: hostForUri);
        final dedupeKey =
            '${cookie.name}|${cookie.path}|${cookie.domain ?? hostForUri}';
        bucketedCookies.putIfAbsent(
          bucketUri,
          () => <String, io.Cookie>{},
        )[dedupeKey] = cookie;
      }

      // 收集所有要同步的 cookie 名称，先清掉 CookieJar 中的同名旧值。
      // 这样 WebView 的值不会被旧的 host-only cookie 覆盖
      // （saveFromResponse 只更新同 domain 类型的 cookie，不同 domain 类型的同名 cookie 会残留）。
      final namesAboutToSync = <String>{};
      for (final cookies in bucketedCookies.values) {
        for (final cookie in cookies.values) {
          if (_isCriticalCookie(cookie.name)) {
            namesAboutToSync.add(cookie.name);
          }
        }
      }
      for (final name in namesAboutToSync) {
        await deleteCookie(name);
      }

      var totalSynced = 0;
      for (final entry in bucketedCookies.entries) {
        final cookies = entry.value.values.toList();
        if (cookies.isEmpty) continue;
        await _cookieJar!.saveFromResponse(entry.key, cookies);
        totalSynced += cookies.length;
      }

      debugPrint('[CookieJar] Synced $totalSynced cookies from WebView');
      if (io.Platform.isWindows) {
        await _logWindowsCookieSyncStatus(
          'syncFromWebView',
          webViewCookies: webViewCookies.values
              .map((snapshot) => snapshot.cookie)
              .toList(),
        );
      }
    } catch (e) {
      debugPrint('[CookieJar] Failed to sync from WebView: $e');
    }
  }

  /// 从 CookieJar 同步 Cookie 到 WebView
  Future<void> syncToWebView({
    String? currentUrl,
    InAppWebViewController? controller,
  }) async {
    if (!_initialized) await initialize();

    try {
      final uri = Uri.parse(AppConstants.baseUrl);
      final extraHosts = <String>{};
      final currentHost = Uri.tryParse(
        currentUrl ?? '',
      )?.host.trim().toLowerCase();
      if (currentHost != null &&
          currentHost.isNotEmpty &&
          (currentHost == uri.host || currentHost.endsWith('.${uri.host}'))) {
        extraHosts.add(currentHost);
      }

      // 收集主域及所有子域的 cookie，保留来源 host 用于 host-only cookie
      final relatedHosts = await _getRelatedHosts(
        uri.host,
        extraHosts: extraHosts,
      );
      final seen = <String>{};
      final windowsCriticalCookies = <String, (io.Cookie, String)>{};
      final cookies = <(io.Cookie, String)>[];
      for (final host in relatedHosts) {
        final hostCookies = await _cookieJar!.loadForRequest(
          Uri.parse('https://$host'),
        );
        for (final c in hostCookies) {
          if (io.Platform.isWindows && _isCriticalCookie(c.name)) {
            // 只按 name+path 去重，不含 domain，
            // 避免 host-only（domain=null）和 domain cookie（.linux.do）同时被收集
            final selectionKey = '${c.name}|${c.path ?? "/"}';
            final existing = windowsCriticalCookies[selectionKey];
            if (existing == null ||
                _compareWindowsCriticalCookieCandidates(
                      c,
                      existing.$1,
                      requestHost: host,
                    ) >
                    0) {
              windowsCriticalCookies[selectionKey] = (c, host);
            }
            continue;
          }
          final dedupeKey = _buildJarToWebViewSyncKey(c, host);
          if (seen.add(dedupeKey)) {
            cookies.add((c, host));
          }
        }
      }
      cookies.insertAll(0, windowsCriticalCookies.values);

      // 清除 WebView 中现有的 cookie
      // 1. 对每个相关 host 做一次无 domain 的批量删除，优先清掉旧 host-only 副本。
      for (final host in relatedHosts) {
        await _webViewCookieManager.deleteCookies(url: WebUri('https://$host'));
      }
      // 2. 逐个 deleteCookie 精确清除 domain cookie（带前导点的无法被批量删除匹配到）
      //    以及子域 cookie
      for (final host in relatedHosts) {
        final url = 'https://$host';
        final existing = await _webViewCookieManager.getCookies(
          url: WebUri(url),
        );
        for (final wc in existing) {
          final deleteDomains = _buildWebViewDeleteDomains(wc.domain);
          for (final domain in deleteDomains) {
            await _webViewCookieManager.deleteCookie(
              url: WebUri(url),
              name: wc.name,
              domain: domain,
              path: wc.path ?? '/',
            );
          }
        }
      }

      if (cookies.isEmpty) return;

      if (CfChallengeLogger.isEnabled) {
        CfChallengeLogger.logCookieSync(
          direction: 'CookieJar -> WebView',
          cookies: cookies
              .map(
                (e) => CookieLogEntry(
                  name: e.$1.name,
                  domain: e.$1.domain,
                  path: e.$1.path,
                  expires: e.$1.expires,
                  valueLength: e.$1.value.length,
                ),
              )
              .toList(),
        );
      }

      // 设置 cookie 到 WebView
      // Apple 平台：iOS setCookie 的 domain 必须带前导点，否则静默失败
      //   （flutter_inappwebview #338）。对 domain cookie 补前导点，
      //   host-only cookie 用 sourceHost 兜底。
      // Android 平台：保持 cookie.domain 原值（与 0.1.28 一致），
      //   host-only cookie 保持 null，syncFromWebView 读回时存入 hostCookies，
      //   不会覆盖 Dio saveCookies 存入 domainCookies 中的有效副本。
      final isApple = io.Platform.isIOS || io.Platform.isMacOS;
      final cookieMaps = <Map<String, dynamic>>[];
      for (final (cookie, sourceHost) in cookies) {
        final value = CookieValueCodec.decode(cookie.value);
        final attempts = _buildWebViewWriteAttempts(cookie, sourceHost);
        final shouldVerifyReadback =
            io.Platform.isWindows &&
            _shouldVerifyWindowsCookieReadback(cookie, sourceHost);
        _WebViewCookieWriteAttempt? appliedAttempt;

        for (final attempt in attempts) {
          final didSet = await _webViewCookieManager.setCookie(
            url: WebUri(attempt.url),
            name: cookie.name,
            value: value.isEmpty ? ' ' : value,
            domain: attempt.domain,
            path: cookie.path ?? '/',
            isSecure: cookie.secure,
            isHttpOnly: cookie.httpOnly,
            expiresDate: cookie.expires?.millisecondsSinceEpoch,
          );

          if (!didSet) {
            continue;
          }

          if (shouldVerifyReadback) {
            final syncedCookie = await _webViewCookieManager.getCookie(
              url: WebUri(attempt.url),
              name: cookie.name,
            );
            final syncedValue = syncedCookie?.value.trim();
            if (syncedValue != null && syncedValue == value) {
              appliedAttempt = attempt;
              break;
            }
            debugPrint(
              '[CookieJar][Windows] Cookie readback mismatch after syncToWebView: '
              'name=${cookie.name}, domain=${attempt.domain}, url=${attempt.url}',
            );
            if (io.Platform.isWindows && _isCriticalCookie(cookie.name)) {
              await _webViewCookieManager.deleteCookie(
                url: WebUri(attempt.url),
                name: cookie.name,
                domain: attempt.domain,
                path: cookie.path ?? '/',
              );
            }
            continue;
          }

          appliedAttempt = attempt;
          break;
        }

        if (appliedAttempt == null) {
          debugPrint(
            '[CookieJar] Failed to write cookie to WebView: ${cookie.name}',
          );
          continue;
        }

        if (isApple) {
          cookieMaps.add({
            'url': appliedAttempt.url,
            'name': cookie.name,
            'value': value.isEmpty ? ' ' : value,
            'domain': appliedAttempt.domain,
            'path': cookie.path ?? '/',
            'isSecure': cookie.secure,
            'isHttpOnly': cookie.httpOnly,
            'expiresDate': cookie.expires?.millisecondsSinceEpoch,
          });
        }
      }

      // Apple 平台：同时写入 HTTPCookieStorage.shared
      if (io.Platform.isMacOS || io.Platform.isIOS) {
        try {
          await _nativeCookieChannel.invokeMethod(
            'clearCookies',
            AppConstants.baseUrl,
          );
          await _nativeCookieChannel.invokeMethod('setCookies', cookieMaps);
        } catch (e) {
          debugPrint('[CookieJar] HTTPCookieStorage sync failed: $e');
        }
      }

      debugPrint('[CookieJar] Synced ${cookies.length} cookies to WebView');
      if (io.Platform.isWindows) {
        await _logWindowsDuplicateCriticalCookies(
          'syncToWebView',
          relatedHosts,
        );
        await _logWindowsCookieSyncStatus('syncToWebView');
      }
    } catch (e) {
      debugPrint('[CookieJar] Failed to sync to WebView: $e');
    }
  }

  /// Windows 专用：通过页面级 controller 的 CDP 直接写入 CookieJar 中的 cookie。
  /// CookieManager 通过 environment 内部 WebView 写入，对页面 WebView 不可靠。
  /// 此方法在 InAppWebView 的 onWebViewCreated 中调用，URL 加载前执行。
  Future<void> syncToWebViewViaController(
    InAppWebViewController controller, {
    String? currentUrl,
  }) async {
    if (!io.Platform.isWindows) return;
    if (!_initialized) await initialize();

    try {
      final uri = Uri.parse(AppConstants.baseUrl);
      final extraHosts = <String>{};
      final currentHost = Uri.tryParse(currentUrl ?? '')?.host.trim().toLowerCase();
      if (currentHost != null &&
          currentHost.isNotEmpty &&
          (currentHost == uri.host || currentHost.endsWith('.${uri.host}'))) {
        extraHosts.add(currentHost);
      }

      final relatedHosts = await _getRelatedHosts(uri.host, extraHosts: extraHosts);
      // 按 name|path 去重：同名 cookie 只保留一份，优先 domain 版本
      final bestCookies = <String, (io.Cookie, String)>{};
      for (final host in relatedHosts) {
        final hostCookies = await _cookieJar!.loadForRequest(Uri.parse('https://$host'));
        for (final c in hostCookies) {
          final key = '${c.name}|${c.path ?? "/"}';
          final existing = bestCookies[key];
          if (existing == null) {
            bestCookies[key] = (c, host);
          } else if (existing.$1.domain == null && c.domain != null) {
            // domain 版本优先于 host-only
            bestCookies[key] = (c, host);
          }
        }
      }
      final cookies = bestCookies.values.toList();

      if (cookies.isEmpty) return;

      var written = 0;
      for (final (cookie, sourceHost) in cookies) {
        final value = CookieValueCodec.decode(cookie.value);
        final normalizedDomain = _normalizeWebViewCookieDomain(cookie.domain);

        String cdpUrl;
        String? cdpDomain;
        if (normalizedDomain != null) {
          cdpUrl = 'https://$normalizedDomain';
          // Dart 的 Cookie 类会去掉前导点，需要补回
          cdpDomain = cookie.domain!.startsWith('.')
              ? cookie.domain
              : '.$normalizedDomain';
        } else {
          cdpUrl = 'https://$sourceHost';
          cdpDomain = null;
        }

        final params = <String, dynamic>{
          'url': cdpUrl,
          'name': cookie.name,
          'value': value.isEmpty ? ' ' : value,
          'path': cookie.path ?? '/',
          'secure': cookie.secure,
          'httpOnly': cookie.httpOnly,
        };
        if (cdpDomain != null) {
          params['domain'] = cdpDomain;
        }
        if (cookie.expires != null) {
          params['expires'] = cookie.expires!.millisecondsSinceEpoch / 1000.0;
        }

        try {
          await controller.callDevToolsProtocolMethod(
            methodName: 'Network.setCookie',
            parameters: params,
          );
          written++;
        } catch (e) {
          debugPrint('[CookieJar][Windows] CDP setCookie failed: ${cookie.name}, $e');
        }
      }

      debugPrint('[CookieJar][Windows] syncToWebViewViaController: $written/${cookies.length} cookies');
    } catch (e) {
      debugPrint('[CookieJar][Windows] syncToWebViewViaController failed: $e');
    }
  }

  /// Windows 专用：通过页面级 controller 的 CDP 读取 cookie 并存入 CookieJar。
  /// CookieManager 通过 environment 内部 WebView 读取，domain 前导点可能丢失，
  /// 导致 domain cookie 被错误存为 host-only。
  Future<void> _syncFromWebViewViaController(
    InAppWebViewController controller, {
    required Uri baseUri,
    String? currentUrl,
    Set<String> extraHosts = const {},
  }) async {
    final resolvedCurrentUrl =
        currentUrl ?? (await controller.getUrl())?.toString();
    final relatedHosts = await _getRelatedHosts(
      baseUri.host,
      extraHosts: extraHosts,
    );
    final cdpUrls = <String>{
      AppConstants.baseUrl,
      '${AppConstants.baseUrl}/',
      if (resolvedCurrentUrl != null && resolvedCurrentUrl.isNotEmpty)
        resolvedCurrentUrl,
      for (final host in relatedHosts) 'https://$host',
    }.toList();

    try {
      final result = await controller.callDevToolsProtocolMethod(
        methodName: 'Network.getCookies',
        parameters: {'urls': cdpUrls},
      );
      final rawCookies = result is Map<String, dynamic>
          ? result['cookies']
          : null;
      if (rawCookies is! List || rawCookies.isEmpty) {
        debugPrint('[CookieJar][Windows] syncFromWebView(controller): no cookies');
        return;
      }

      // 按 name|path 去重，优先 domain 版本
      final bestCookies = <String, Map<String, dynamic>>{};
      for (final raw in rawCookies.whereType<Map>()) {
        final name = raw['name']?.toString();
        final domain = raw['domain']?.toString() ?? '';
        if (name == null) continue;
        // 只保留与 baseHost 相关的 cookie
        final normalized = domain.replaceFirst(RegExp(r'^\.'), '');
        if (normalized.isNotEmpty &&
            normalized != baseUri.host &&
            !normalized.endsWith('.${baseUri.host}') &&
            !baseUri.host.endsWith('.$normalized')) {
          continue;
        }
        final path = raw['path']?.toString() ?? '/';
        final key = '$name|$path';
        final existing = bestCookies[key];
        if (existing == null ||
            (!(existing['domain']?.toString().startsWith('.') ?? false) &&
                domain.startsWith('.'))) {
          bestCookies[key] = Map<String, dynamic>.from(
            raw.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      }

      // 存入 CookieJar
      final bucketedCookies = <Uri, Map<String, io.Cookie>>{};
      for (final raw in bestCookies.values) {
        final name = raw['name'].toString();
        final value = raw['value']?.toString() ?? '';
        final rawDomain = raw['domain']?.toString().trim();
        final isDomainCookie = rawDomain != null && rawDomain.startsWith('.');
        final normalizedDomain = rawDomain != null
            ? (rawDomain.startsWith('.') ? rawDomain.substring(1) : rawDomain)
            : null;

        io.Cookie cookie;
        try {
          cookie = io.Cookie(name, value);
        } catch (_) {
          cookie = io.Cookie(name, CookieValueCodec.encode(value));
        }
        cookie
          ..path = raw['path']?.toString() ?? '/'
          ..secure = raw['secure'] == true
          ..httpOnly = raw['httpOnly'] == true;

        if (isDomainCookie && normalizedDomain != null) {
          cookie.domain = '.$normalizedDomain';
        }

        final expiresRaw = raw['expires'];
        if (expiresRaw is num && expiresRaw > 0) {
          cookie.expires = DateTime.fromMillisecondsSinceEpoch(
            (expiresRaw * 1000).round(),
          );
        }

        if (cookie.expires != null && cookie.expires!.isBefore(DateTime.now())) {
          continue;
        }
        if (cookie.value.isEmpty && _isCriticalCookie(cookie.name)) {
          continue;
        }

        final hostForUri = normalizedDomain ?? baseUri.host;
        final bucketUri = Uri(scheme: baseUri.scheme, host: hostForUri);
        final dedupeKey = '${cookie.name}|${cookie.path}|${cookie.domain ?? hostForUri}';
        bucketedCookies
            .putIfAbsent(bucketUri, () => <String, io.Cookie>{})
            [dedupeKey] = cookie;
      }

      // 先清掉关键 cookie 旧值
      final namesAboutToSync = <String>{};
      for (final cookies in bucketedCookies.values) {
        for (final cookie in cookies.values) {
          if (_isCriticalCookie(cookie.name)) {
            namesAboutToSync.add(cookie.name);
          }
        }
      }
      for (final name in namesAboutToSync) {
        await deleteCookie(name);
      }

      var totalSynced = 0;
      for (final entry in bucketedCookies.entries) {
        final cookies = entry.value.values.toList();
        if (cookies.isEmpty) continue;
        await _cookieJar!.saveFromResponse(entry.key, cookies);
        totalSynced += cookies.length;
      }

      debugPrint(
        '[CookieJar][Windows] syncFromWebView(controller): $totalSynced cookies',
      );
      await _logWindowsCookieSyncStatus('syncFromWebView(controller)');
    } catch (e) {
      debugPrint('[CookieJar][Windows] syncFromWebView(controller) failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 单个 Cookie 操作
  // ---------------------------------------------------------------------------

  /// 获取指定 Cookie 的值
  /// 优先返回 host-only cookie（服务器 Set-Cookie 直接设置的最新值），
  /// 与 AppCookieManager._mergeCookies 的发送优先级保持一致。
  Future<String?> getCookieValue(String name) async {
    if (!_initialized) await initialize();

    try {
      final uri = Uri.parse(AppConstants.baseUrl);
      final cookies = await _cookieJar!.loadForRequest(uri);

      String? fallback;
      for (final cookie in cookies) {
        if (cookie.name == name) {
          if (cookie.domain == null) {
            return CookieValueCodec.decode(cookie.value);
          }
          fallback ??= CookieValueCodec.decode(cookie.value);
        }
      }
      return fallback;
    } catch (e) {
      debugPrint('[CookieJar] Failed to get cookie $name: $e');
    }
    return null;
  }

  /// 设置 Cookie
  Future<void> setCookie(
    String name,
    String value, {
    String? url,
    String? domain,
    String? path,
    DateTime? expires,
    bool secure = true,
    bool httpOnly = false,
  }) async {
    if (!_initialized) await initialize();

    try {
      final uri =
          Uri.tryParse(url ?? AppConstants.baseUrl) ??
          Uri.parse(AppConstants.baseUrl);
      final cookie = io.Cookie(name, value)
        ..path = path ?? '/'
        ..secure = secure
        ..httpOnly = httpOnly;

      final normalizedDomain = domain?.trim();
      if (normalizedDomain != null && normalizedDomain.isNotEmpty) {
        cookie.domain = normalizedDomain;
      }
      if (expires != null) {
        cookie.expires = expires;
      }

      await _cookieJar!.saveFromResponse(uri, [cookie]);
    } catch (e) {
      debugPrint('[CookieJar] Failed to set cookie $name: $e');
    }
  }

  /// 删除指定 Cookie（遍历所有相关 host，删除所有匹配 name 的 cookie）
  Future<void> deleteCookie(String name) async {
    if (!_initialized) await initialize();

    try {
      final uri = Uri.parse(AppConstants.baseUrl);
      final expired = DateTime.now().subtract(const Duration(days: 1));
      final relatedHosts = await _getRelatedHosts(uri.host);

      for (final host in relatedHosts) {
        final hostUri = Uri.parse('https://$host');
        final cookies = await _cookieJar!.loadForRequest(hostUri);
        final expiredCookies = <io.Cookie>[];

        for (final cookie in cookies) {
          if (cookie.name == name) {
            final expired0 = io.Cookie(name, '')
              ..path = cookie.path ?? '/'
              ..expires = expired;
            if (cookie.domain != null) {
              expired0.domain = cookie.domain;
            }
            expiredCookies.add(expired0);
          }
        }

        if (expiredCookies.isNotEmpty) {
          await _cookieJar!.saveFromResponse(hostUri, expiredCookies);
        }
      }
    } catch (e) {
      debugPrint('[CookieJar] Failed to delete cookie $name: $e');
    }
  }

  /// 清除所有 Cookie
  Future<void> clearAll() async {
    if (!_initialized) return;

    try {
      await _cookieJar!.deleteAll();
      await _webViewCookieManager.deleteAllCookies();

      // Apple 平台：同时清除 HTTPCookieStorage.shared，
      // 否则 sharedCookiesEnabled=true 的 WebView 创建时会读到旧 cookie。
      if (io.Platform.isMacOS || io.Platform.isIOS) {
        try {
          await _nativeCookieChannel.invokeMethod(
            'clearCookies',
            AppConstants.baseUrl,
          );
        } catch (e) {
          debugPrint('[CookieJar] HTTPCookieStorage clear failed: $e');
        }
      }
    } catch (e) {
      debugPrint('[CookieJar] Failed to clear cookies: $e');
    }
  }

  /// 获取所有 Cookie 的字符串形式（用于请求头）
  Future<String?> getCookieHeader() async {
    if (!_initialized) await initialize();

    try {
      final uri = Uri.parse(AppConstants.baseUrl);
      final cookies = await _cookieJar!.loadForRequest(uri);

      if (cookies.isEmpty) return null;

      return cookies
          .map((c) => '${c.name}=${CookieValueCodec.decode(c.value)}')
          .join('; ');
    } catch (e) {
      debugPrint('[CookieJar] Failed to get cookie header: $e');
      return null;
    }
  }

  /// 获取 _t token
  Future<String?> getTToken() => getCookieValue('_t');

  /// 从当前 WebView 控制器的实时 Cookie 中读取指定值
  /// Windows 上优先使用 DevTools cookie 视图，兜底 CookieManager 读不到的场景。
  Future<String?> readCookieValueFromController(
    InAppWebViewController controller,
    String name, {
    String? currentUrl,
  }) async {
    if (!io.Platform.isWindows) {
      return null;
    }

    try {
      final liveCookies = await _readLiveCookiesFromController(
        controller,
        currentUrl: currentUrl,
      );
      _DevToolsCookieSnapshot? fallback;
      for (final cookie in liveCookies) {
        if (cookie.name != name) {
          continue;
        }
        if (_matchesAppHost(cookie.domain) && cookie.value.isNotEmpty) {
          return cookie.value;
        }
        fallback ??= cookie;
      }
      return fallback?.value;
    } catch (e) {
      debugPrint('[CookieJar][Windows] Failed to read live cookie $name: $e');
      return null;
    }
  }

  /// 将当前 WebView 控制器里的关键实时 Cookie 直接回写到 CookieJar。
  /// 用于 Windows 上 CookieManager 读不到、但 DevTools 已经可见的场景。
  Future<void> syncCriticalCookiesFromController(
    InAppWebViewController controller, {
    String? currentUrl,
    Set<String>? cookieNames,
  }) async {
    if (!_initialized) await initialize();
    if (!io.Platform.isWindows) {
      return;
    }

    final names = cookieNames ?? const {'_t', '_forum_session', 'cf_clearance'};

    try {
      final liveCookies = await _readLiveCookiesFromController(
        controller,
        currentUrl: currentUrl,
      );
      if (liveCookies.isEmpty) {
        return;
      }

      var synced = 0;
      for (final cookie in liveCookies) {
        if (!names.contains(cookie.name)) {
          continue;
        }
        if (!_matchesAppHost(cookie.domain) || cookie.value.isEmpty) {
          continue;
        }

        await setCookie(
          cookie.name,
          cookie.value,
          url: currentUrl,
          domain: cookie.persistedDomain,
          path: cookie.path,
          expires: cookie.expires,
          secure: cookie.secure,
          httpOnly: cookie.httpOnly,
        );
        synced++;
      }

      if (synced > 0) {
        debugPrint(
          '[CookieJar][Windows] Synced $synced live cookies from controller: ${names.join(", ")}',
        );
      }
    } catch (e) {
      debugPrint('[CookieJar][Windows] Failed to sync live cookies: $e');
    }
  }

  /// 获取 _t 的诊断信息（所有副本的元数据，不含实际值）
  Future<Map<String, dynamic>> getTTokenDiagnostics() async {
    if (!_initialized) await initialize();
    try {
      final uri = Uri.parse(AppConstants.baseUrl);
      final cookies = await _cookieJar!.loadForRequest(uri);
      final tCookies = cookies.where((c) => c.name == '_t').toList();
      return {
        'count': tCookies.length,
        'variants': tCookies
            .map(
              (c) => {
                'domain': c.domain,
                'path': c.path,
                'len': c.value.length,
                'hasPrefix': c.value.startsWith(CookieValueCodec._prefix),
              },
            )
            .toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// 获取 cf_clearance
  Future<String?> getCfClearance() => getCookieValue('cf_clearance');

  /// 获取 cf_clearance 的原始 Cookie 对象（保留 domain、expires 等属性）
  Future<io.Cookie?> getCfClearanceCookie() async {
    if (!_initialized) await initialize();
    try {
      final uri = Uri.parse(AppConstants.baseUrl);
      final cookies = await _cookieJar!.loadForRequest(uri);
      io.Cookie? fallback;
      for (final cookie in cookies) {
        if (cookie.name == 'cf_clearance') {
          if (cookie.domain != null) return cookie;
          fallback ??= cookie;
        }
      }
      return fallback;
    } catch (e) {
      debugPrint('[CookieJar] Failed to get cf_clearance cookie: $e');
    }
    return null;
  }

  /// 恢复 cf_clearance（登出清除 cookie 后调用）
  Future<void> restoreCfClearance(io.Cookie cookie) async {
    if (!_initialized) await initialize();
    try {
      final uri = Uri.parse(AppConstants.baseUrl);
      await _cookieJar!.saveFromResponse(uri, [cookie]);
    } catch (e) {
      debugPrint('[CookieJar] Failed to restore cf_clearance: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 私有工具方法
  // ---------------------------------------------------------------------------

  Future<Map<String, _CollectedWebViewCookie>> _collectWebViewCookies(
    String baseHost, {
    Set<String>? extraHosts,
  }) async {
    final relatedHosts = {
      ...await _getRelatedHosts(baseHost),
      ...?extraHosts,
    }.toList();
    final collected = <String, _CollectedWebViewCookie>{};

    for (final host in relatedHosts) {
      final url = 'https://$host';
      final hostCookies = await _webViewCookieManager.getCookies(
        url: WebUri(url),
      );
      for (final wc in hostCookies) {
        final normalizedDomain =
            _normalizeWebViewCookieDomain(wc.domain) ?? host;
        final key =
            '${wc.name}|$normalizedDomain|${wc.path ?? '/'}|${wc.value.hashCode}';
        final snapshot = collected.putIfAbsent(
          key,
          () => _CollectedWebViewCookie(cookie: wc, primaryHost: host),
        );
        snapshot.sourceHosts.add(host);
      }
    }

    return collected;
  }

  String? _normalizeWebViewCookieDomain(String? rawDomain) {
    final trimmed = rawDomain?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed.startsWith('.') ? trimmed.substring(1) : trimmed;
  }

  /// flutter_inappwebview Windows 插件当前把 WebView2 DevTools 的 expires
  /// 直接回传成秒级时间戳，但 Dart 侧类型声明是毫秒。
  /// 这里做兼容：小于 1e11 的值按秒处理，其余按毫秒处理。
  DateTime? _parseWebViewCookieExpires(int? rawExpiresDate) {
    if (rawExpiresDate == null || rawExpiresDate <= 0) {
      return null;
    }

    final normalizedMillis = rawExpiresDate < 100000000000
        ? rawExpiresDate * 1000
        : rawExpiresDate;
    return DateTime.fromMillisecondsSinceEpoch(normalizedMillis);
  }

  bool _shouldPersistWebViewDomainCookie({
    required String? rawDomain,
    required String? normalizedDomain,
    required Set<String> sourceHosts,
  }) {
    if (normalizedDomain == null) {
      return false;
    }
    if (rawDomain != null && rawDomain.trim().startsWith('.')) {
      return true;
    }
    for (final sourceHost in sourceHosts) {
      if (sourceHost != normalizedDomain &&
          sourceHost.endsWith('.$normalizedDomain')) {
        return true;
      }
    }
    return false;
  }

  List<String?> _buildWebViewDeleteDomains(String? domain) {
    final domains = <String?>{domain};
    final trimmed = domain?.trim();
    if (io.Platform.isWindows && trimmed != null && trimmed.isNotEmpty) {
      if (trimmed.startsWith('.')) {
        domains.add(trimmed.substring(1));
      } else {
        domains.add('.$trimmed');
      }
    }
    return domains.toList();
  }

  List<_WebViewCookieWriteAttempt> _buildWebViewWriteAttempts(
    io.Cookie cookie,
    String sourceHost,
  ) {
    final attempts = <_WebViewCookieWriteAttempt>[];
    final seen = <String>{};

    void addAttempt(String host, {String? domain}) {
      final normalizedHost = host.trim();
      if (normalizedHost.isEmpty) {
        return;
      }
      final normalizedDomain = domain?.trim();
      final key = '${normalizedDomain ?? ''}|$normalizedHost';
      if (!seen.add(key)) {
        return;
      }
      attempts.add(
        _WebViewCookieWriteAttempt(
          url: 'https://$normalizedHost',
          domain: normalizedDomain,
        ),
      );
    }

    final normalizedCookieDomain = _normalizeWebViewCookieDomain(cookie.domain);
    final isApple = io.Platform.isIOS || io.Platform.isMacOS;

    if (io.Platform.isWindows && _isCriticalCookie(cookie.name)) {
      // 保留原始 domain 属性，不再强制 host-only
      if (normalizedCookieDomain != null) {
        final exactDomain = cookie.domain?.trim();
        addAttempt(normalizedCookieDomain, domain: exactDomain);
      } else {
        // 原始 domain 为 null（host-only），保持 host-only
        addAttempt(sourceHost, domain: null);
      }
      return attempts;
    }

    if (isApple) {
      if (normalizedCookieDomain != null) {
        addAttempt(normalizedCookieDomain, domain: '.$normalizedCookieDomain');
      } else {
        addAttempt(sourceHost, domain: sourceHost);
      }
      return attempts;
    }

    if (io.Platform.isWindows && normalizedCookieDomain != null) {
      final exactDomain = cookie.domain?.trim();
      if (exactDomain != null && exactDomain.isNotEmpty) {
        addAttempt(normalizedCookieDomain, domain: exactDomain);
      }
      if (exactDomain != null && exactDomain.startsWith('.')) {
        addAttempt(normalizedCookieDomain, domain: normalizedCookieDomain);
      } else {
        addAttempt(normalizedCookieDomain, domain: '.$normalizedCookieDomain');
      }
      return attempts;
    }

    if (io.Platform.isWindows && normalizedCookieDomain == null) {
      addAttempt(sourceHost, domain: null);

      final baseHost = Uri.parse(AppConstants.baseUrl).host;
      if (sourceHost != baseHost) {
        addAttempt(sourceHost, domain: sourceHost);
      }
      return attempts;
    }

    addAttempt(
      normalizedCookieDomain ?? sourceHost,
      domain: cookie.domain?.trim(),
    );
    return attempts;
  }

  bool _shouldVerifyWindowsCookieReadback(io.Cookie cookie, String sourceHost) {
    // 关键 cookie 不做 readback 验证：
    // 1. setCookie 返回值不可信（CDP 文档：success always true）
    // 2. getCookie readback 可能读到旧值或空值，导致误删刚写入的 cookie
    if (_isCriticalCookie(cookie.name)) {
      return false;
    }

    final baseHost = Uri.parse(AppConstants.baseUrl).host;
    return cookie.domain == null && sourceHost != baseHost;
  }

  /// CookieJar -> WebView 同步去重键。
  ///
  /// domain cookie 以 domain 为作用域去重即可；
  /// host-only cookie 不能只看 name/path，因为不同子域上的 host-only cookie
  /// 在 CookieJar 中 domain 都是 null，会被错误合并。
  String _buildJarToWebViewSyncKey(io.Cookie cookie, String sourceHost) {
    final normalizedDomain = cookie.domain?.trim();
    final normalizedPath = cookie.path ?? '/';
    if (normalizedDomain != null && normalizedDomain.isNotEmpty) {
      return '${cookie.name}|$normalizedDomain|$normalizedPath';
    }
    return '${cookie.name}|host-only|${sourceHost.trim().toLowerCase()}|$normalizedPath';
  }

  int _compareWindowsCriticalCookieCandidates(
    io.Cookie candidate,
    io.Cookie existing, {
    required String requestHost,
  }) {
    final scoreDiff =
        _scoreWindowsCriticalCookieCandidate(candidate, requestHost) -
        _scoreWindowsCriticalCookieCandidate(existing, requestHost);
    if (scoreDiff != 0) {
      return scoreDiff;
    }

    final candidateExpires = candidate.expires;
    final existingExpires = existing.expires;
    if (candidateExpires != null && existingExpires == null) {
      return 1;
    }
    if (candidateExpires == null && existingExpires != null) {
      return -1;
    }
    if (candidateExpires != null && existingExpires != null) {
      final expiryDiff = candidateExpires.compareTo(existingExpires);
      if (expiryDiff != 0) {
        return expiryDiff;
      }
    }

    return candidate.value.length.compareTo(existing.value.length);
  }

  int _scoreWindowsCriticalCookieCandidate(
    io.Cookie cookie,
    String requestHost,
  ) {
    if (cookie.domain == null) {
      return 400;
    }

    final normalizedDomain = _normalizeWebViewCookieDomain(cookie.domain);
    if (normalizedDomain == null) {
      return 100;
    }
    if (normalizedDomain == requestHost) {
      return 300;
    }
    if (requestHost.endsWith('.$normalizedDomain')) {
      return 200 + normalizedDomain.length;
    }
    return 100;
  }

  Future<List<_DevToolsCookieSnapshot>> _readLiveCookiesFromController(
    InAppWebViewController controller, {
    String? currentUrl,
  }) async {
    if (!io.Platform.isWindows) {
      return const [];
    }

    final resolvedCurrentUrl =
        currentUrl ?? (await controller.getUrl())?.toString();

    final urls = <String>{
      AppConstants.baseUrl,
      '${AppConstants.baseUrl}/',
      if (resolvedCurrentUrl != null && resolvedCurrentUrl.isNotEmpty)
        resolvedCurrentUrl,
    }.toList();

    final result = await controller.callDevToolsProtocolMethod(
      methodName: 'Network.getCookies',
      parameters: {'urls': urls},
    );
    final rawCookies = result is Map<String, dynamic>
        ? result['cookies']
        : null;
    if (rawCookies is! List) {
      return const [];
    }

    final cookies = rawCookies
        .whereType<Map>()
        .map(
          (raw) => _DevToolsCookieSnapshot.fromMap(
            raw.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .whereType<_DevToolsCookieSnapshot>()
        .toList();

    if (cookies.isNotEmpty) {
      final names = cookies.map((e) => e.name).toSet().join(', ');
      debugPrint('[CookieJar][Windows] DevTools cookies: [$names]');
    }

    return cookies;
  }

  bool _matchesAppHost(String? domain) {
    final baseHost = Uri.parse(AppConstants.baseUrl).host;
    final normalized = domain?.trim().replaceFirst(RegExp(r'^\.'), '');
    if (normalized == null || normalized.isEmpty) {
      return true;
    }
    return normalized == baseHost || normalized.endsWith('.$baseHost');
  }

  Future<void> _logWindowsCookieSyncStatus(
    String phase, {
    List<Cookie>? webViewCookies,
  }) async {
    if (!io.Platform.isWindows) {
      return;
    }

    final baseHost = Uri.parse(AppConstants.baseUrl).host;
    final relatedHosts = await _getRelatedHosts(baseHost);

    final effectiveWebViewCookies =
        webViewCookies ??
        (await _collectWebViewCookies(
          baseHost,
        )).values.map((snapshot) => snapshot.cookie).toList();

    final jarCookies = <io.Cookie>[];
    final seenJarKeys = <String>{};
    for (final host in relatedHosts) {
      final hostCookies = await _cookieJar!.loadForRequest(
        Uri.parse('https://$host'),
      );
      for (final cookie in hostCookies) {
        final key =
            '${cookie.name}|${cookie.domain}|${cookie.path}|${cookie.value.hashCode}';
        if (seenJarKeys.add(key)) {
          jarCookies.add(cookie);
        }
      }
    }

    final missingInJar = <String>[];
    final missingInWebView = <String>[];
    final diagnostics = <String>[];

    for (final name in const ['_t', '_forum_session', 'cf_clearance']) {
      final webViewCookie = _pickWebViewCookie(effectiveWebViewCookies, name);
      final jarCookie = _pickJarCookie(jarCookies, name);

      if (webViewCookie != null && jarCookie == null) {
        missingInJar.add(name);
      }
      if (jarCookie != null && webViewCookie == null) {
        missingInWebView.add(name);
      }

      diagnostics.add(
        '$name(wv=${_formatWebViewCookieState(webViewCookie)}, '
        'jar=${_formatJarCookieState(jarCookie)})',
      );
    }

    final hasMismatch = missingInJar.isNotEmpty || missingInWebView.isNotEmpty;
    if (kDebugMode || hasMismatch) {
      debugPrint('[CookieJar][Windows] $phase ${diagnostics.join(', ')}');
    }
    if (hasMismatch) {
      debugPrint(
        '[CookieJar][Windows] $phase mismatch: '
        'missingInJar=$missingInJar, missingInWebView=$missingInWebView',
      );
    }
  }

  Future<void> _logWindowsDuplicateCriticalCookies(
    String phase,
    Iterable<String> hosts,
  ) async {
    if (!io.Platform.isWindows) {
      return;
    }

    for (final host in hosts) {
      final cookies = await _webViewCookieManager.getCookies(
        url: WebUri('https://$host'),
      );
      final grouped = <String, List<Cookie>>{};
      for (final cookie in cookies) {
        if (!_isCriticalCookie(cookie.name)) {
          continue;
        }
        final key = '${cookie.name}|${cookie.path ?? "/"}';
        grouped.putIfAbsent(key, () => <Cookie>[]).add(cookie);
      }

      final duplicates = grouped.entries
          .where((entry) => entry.value.length > 1)
          .map((entry) {
            final name = entry.key.split('|').first;
            final states = entry.value
                .map(
                  (cookie) =>
                      '${cookie.domain ?? "host-only"}:${cookie.value.length}',
                )
                .join(', ');
            return '$name($states)';
          })
          .toList();

      if (duplicates.isNotEmpty) {
        debugPrint(
          '[CookieJar][Windows] $phase duplicate critical cookies on $host: '
          '${duplicates.join('; ')}',
        );
      }
    }
  }

  Cookie? _pickWebViewCookie(List<Cookie> cookies, String name) {
    Cookie? fallback;
    for (final cookie in cookies) {
      if (cookie.name != name) {
        continue;
      }
      if (cookie.value.isNotEmpty) {
        return cookie;
      }
      fallback ??= cookie;
    }
    return fallback;
  }

  io.Cookie? _pickJarCookie(List<io.Cookie> cookies, String name) {
    io.Cookie? fallback;
    for (final cookie in cookies) {
      if (cookie.name != name) {
        continue;
      }
      if (cookie.domain == null) {
        return cookie;
      }
      fallback ??= cookie;
    }
    return fallback;
  }

  String _formatWebViewCookieState(Cookie? cookie) {
    if (cookie == null) {
      return '-';
    }
    return '${cookie.value.length}:${cookie.domain ?? "host-only"}';
  }

  String _formatJarCookieState(io.Cookie? cookie) {
    if (cookie == null) {
      return '-';
    }
    return '${CookieValueCodec.decode(cookie.value).length}:${cookie.domain ?? "host-only"}';
  }

  /// 从 cookie jar 存储中获取所有与 [baseHost] 相关的域名（主域 + 子域）
  Future<List<String>> _getRelatedHosts(
    String baseHost, {
    Set<String>? extraHosts,
  }) async {
    bool isRelatedHost(String host) {
      return host == baseHost || host.endsWith('.$baseHost');
    }

    final hosts = <String>{baseHost, ...?extraHosts?.where(isRelatedHost)};
    final jar = _cookieJar;
    if (jar is DefaultCookieJar) {
      for (final host in jar.domainCookies.keys) {
        final normalizedHost = host.trim().replaceFirst(RegExp(r'^\.'), '');
        if (normalizedHost.isNotEmpty && isRelatedHost(normalizedHost)) {
          hosts.add(normalizedHost);
        }
      }
      for (final host in jar.hostCookies.keys) {
        final normalizedHost = host.trim().toLowerCase();
        if (normalizedHost.isNotEmpty && isRelatedHost(normalizedHost)) {
          hosts.add(normalizedHost);
        }
      }
    }
    if (jar is PersistCookieJar) {
      try {
        await jar.forceInit();
        for (final host in jar.domainCookies.keys) {
          final normalizedHost = host.trim().replaceFirst(RegExp(r'^\.'), '');
          if (normalizedHost.isNotEmpty && isRelatedHost(normalizedHost)) {
            hosts.add(normalizedHost);
          }
        }
        final indexStr = await jar.storage.read('.index');
        if (indexStr != null && indexStr.isNotEmpty) {
          for (final host in (json.decode(indexStr) as List).cast<String>()) {
            final normalizedHost = host.trim().toLowerCase();
            if (normalizedHost.isNotEmpty && isRelatedHost(normalizedHost)) {
              hosts.add(normalizedHost);
            }
          }
        }
      } catch (e) {
        debugPrint('[CookieJar] Failed to read cookie index: $e');
      }
    }
    final relatedHosts = hosts.toList()..sort();
    return relatedHosts;
  }

  /// 是否是关键 cookie（空值不应覆盖 CookieJar 中的有效值）
  static bool _isCriticalCookie(String name) {
    return name == '_t' || name == '_forum_session' || name == 'cf_clearance';
  }
}

class _CollectedWebViewCookie {
  _CollectedWebViewCookie({required this.cookie, required this.primaryHost})
    : sourceHosts = {primaryHost};

  final Cookie cookie;
  final String primaryHost;
  final Set<String> sourceHosts;
}

class _WebViewCookieWriteAttempt {
  const _WebViewCookieWriteAttempt({required this.url, required this.domain});

  final String url;
  final String? domain;
}

class _DevToolsCookieSnapshot {
  const _DevToolsCookieSnapshot({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.expires,
    required this.secure,
    required this.httpOnly,
  });

  final String name;
  final String value;
  final String? domain;
  final String path;
  final DateTime? expires;
  final bool secure;
  final bool httpOnly;

  /// 返回用于 CookieJar 持久化的 domain 属性。
  /// WebView2 CDP 保留前导点：domain cookie 返回 `.linux.do`，
  /// host-only cookie 返回 `linux.do`。只看前导点即可。
  String? get persistedDomain {
    final trimmed = domain?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed.startsWith('.') ? trimmed : null;
  }

  static _DevToolsCookieSnapshot? fromMap(Map<String, dynamic> map) {
    final name = map['name']?.toString();
    final value = map['value']?.toString();
    if (name == null || value == null) {
      return null;
    }

    DateTime? expires;
    final expiresRaw = map['expires'];
    if (expiresRaw is num && expiresRaw > 0) {
      expires = DateTime.fromMillisecondsSinceEpoch(
        (expiresRaw * 1000).round(),
      );
    }

    return _DevToolsCookieSnapshot(
      name: name,
      value: value,
      domain: map['domain']?.toString(),
      path: map['path']?.toString() ?? '/',
      expires: expires,
      secure: map['secure'] == true,
      httpOnly: map['httpOnly'] == true,
    );
  }
}
