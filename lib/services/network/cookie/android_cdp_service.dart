import 'package:flutter/services.dart';

import '../../app_logger.dart';
import 'android_cdp_feature.dart';

class AndroidCdpService {
  static const Duration _getCookiesCacheTtl = Duration(milliseconds: 350);
  static const String _tag = 'AndroidCdp';

  AndroidCdpService._();

  static final AndroidCdpService instance = AndroidCdpService._();

  static const MethodChannel _channel = MethodChannel('com.fluxdo/android_cdp');
  Future<Map<String, dynamic>?>? _pendingGetCookies;
  String? _pendingGetCookiesKey;
  Map<String, dynamic>? _lastGetCookiesResult;
  String? _lastGetCookiesKey;
  DateTime? _lastGetCookiesAt;

  Future<bool> isAvailable() async {
    if (!AndroidCdpFeature.isEnabled) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      final available = result ?? false;
      if (!available) {
        AppLogger.warning('Native CDP isAvailable returned false', tag: _tag);
      }
      return available;
    } on PlatformException catch (e, stackTrace) {
      _logPlatformError('isAvailable', e, stackTrace);
      return false;
    } catch (e, stackTrace) {
      _logUnexpectedError('isAvailable', e, stackTrace);
      return false;
    }
  }

  Future<bool> awaitTargetReady({Duration timeout = const Duration(milliseconds: 2500)}) async {
    if (!AndroidCdpFeature.isEnabled) return false;
    try {
      final result = await _channel.invokeMethod<bool>('awaitTargetReady', {
        'timeoutMs': timeout.inMilliseconds,
      });
      final ready = result ?? false;
      if (!ready) {
        AppLogger.warning(
          'Native CDP target not ready',
          tag: _tag,
        );
      }
      return ready;
    } on PlatformException catch (e, stackTrace) {
      _logPlatformError('awaitTargetReady', e, stackTrace, extras: {
        'timeoutMs': timeout.inMilliseconds,
      });
      return false;
    } catch (e, stackTrace) {
      _logUnexpectedError('awaitTargetReady', e, stackTrace, extras: {
        'timeoutMs': timeout.inMilliseconds,
      });
      return false;
    }
  }

  Future<Map<String, dynamic>?> getCookies(List<String> urls) async {
    if (!AndroidCdpFeature.isEnabled || urls.isEmpty) return null;
    final normalizedUrls = urls.toSet().toList(growable: false)..sort();
    final key = normalizedUrls.join('\n');
    final now = DateTime.now();
    final lastAt = _lastGetCookiesAt;
    if (_lastGetCookiesKey == key &&
        _lastGetCookiesResult != null &&
        lastAt != null &&
        now.difference(lastAt) <= _getCookiesCacheTtl) {
      return Map<String, dynamic>.from(_lastGetCookiesResult!);
    }

    final pending = _pendingGetCookies;
    if (pending != null && _pendingGetCookiesKey == key) {
      return pending;
    }

    final future = _invokeGetCookies(normalizedUrls);
    _pendingGetCookiesKey = key;
    _pendingGetCookies = future;
    try {
      final result = await future;
      _lastGetCookiesKey = key;
      _lastGetCookiesResult =
          result == null ? null : Map<String, dynamic>.from(result);
      _lastGetCookiesAt = DateTime.now();
      return result;
    } finally {
      if (identical(_pendingGetCookies, future)) {
        _pendingGetCookies = null;
        _pendingGetCookiesKey = null;
      }
    }
  }

  Future<Map<String, dynamic>?> _invokeGetCookies(List<String> urls) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getCookies',
        {'urls': urls},
      );
      final map = result == null ? null : Map<String, dynamic>.from(result);
      if (map == null) {
        AppLogger.warning('Native CDP getCookies returned null', tag: _tag);
        return null;
      }
      if (map['ok'] != true) {
        AppLogger.warning(
          'Native CDP getCookies returned ok=false: ${map['error'] ?? 'unknown'}',
          tag: _tag,
        );
      }
      return map;
    } on PlatformException catch (e, stackTrace) {
      _logPlatformError('getCookies', e, stackTrace, extras: {
        'urlCount': urls.length,
      });
      rethrow;
    } catch (e, stackTrace) {
      _logUnexpectedError('getCookies', e, stackTrace, extras: {
        'urlCount': urls.length,
      });
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> setCookie(Map<String, dynamic> params) async {
    if (!AndroidCdpFeature.isEnabled || params.isEmpty) return null;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'setCookie',
        params,
      );
      final map = result == null ? null : Map<String, dynamic>.from(result);
      if (map == null) {
        AppLogger.warning('Native CDP setCookie returned null', tag: _tag);
        return null;
      }
      if (map['ok'] != true) {
        AppLogger.warning(
          'Native CDP setCookie returned ok=false: ${map['error'] ?? 'unknown'}',
          tag: _tag,
        );
      }
      return map;
    } on PlatformException catch (e, stackTrace) {
      _logPlatformError('setCookie', e, stackTrace, extras: {
        'cookieName': params['name'],
        'url': params['url'],
      });
      rethrow;
    } catch (e, stackTrace) {
      _logUnexpectedError('setCookie', e, stackTrace, extras: {
        'cookieName': params['name'],
        'url': params['url'],
      });
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> deleteCookies(Map<String, dynamic> params) async {
    if (!AndroidCdpFeature.isEnabled || params.isEmpty) return null;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'deleteCookies',
        params,
      );
      final map = result == null ? null : Map<String, dynamic>.from(result);
      if (map == null) {
        AppLogger.warning('Native CDP deleteCookies returned null', tag: _tag);
        return null;
      }
      if (map['ok'] != true) {
        AppLogger.warning(
          'Native CDP deleteCookies returned ok=false: ${map['error'] ?? 'unknown'}',
          tag: _tag,
        );
      }
      return map;
    } on PlatformException catch (e, stackTrace) {
      _logPlatformError('deleteCookies', e, stackTrace, extras: {
        'cookieName': params['name'],
        'url': params['url'],
      });
      rethrow;
    } catch (e, stackTrace) {
      _logUnexpectedError('deleteCookies', e, stackTrace, extras: {
        'cookieName': params['name'],
        'url': params['url'],
      });
      rethrow;
    }
  }

  void _logPlatformError(
    String operation,
    PlatformException error,
    StackTrace stackTrace, {
    Map<String, Object?>? extras,
  }) {
    final details = error.details;
    AppLogger.error(
      'Native CDP $operation failed: ${error.message ?? error.code}',
      tag: _tag,
      error: {
        'operation': operation,
        'code': error.code,
        'message': error.message,
        'details': details is Map
            ? Map<String, Object?>.from(details.cast<String, Object?>())
            : details,
        if (extras != null) ...extras,
      },
      stackTrace: stackTrace,
    );
  }

  void _logUnexpectedError(
    String operation,
    Object error,
    StackTrace stackTrace, {
    Map<String, Object?>? extras,
  }) {
    AppLogger.error(
      'Native CDP $operation threw unexpected error',
      tag: _tag,
      error: {
        'operation': operation,
        'error': error.toString(),
        if (extras != null) ...extras,
      },
      stackTrace: stackTrace,
    );
  }
}
