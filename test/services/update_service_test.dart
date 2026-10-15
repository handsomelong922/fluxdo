import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Preferences implements SharedPreferences {
  final values = <String, Object>{};
  final writes = <String>[];
  String? failKey;

  @override
  String? getString(String key) => values[key] as String?;
  @override
  int? getInt(String key) => values[key] as int?;
  @override
  Future<bool> remove(String key) async {
    writes.add('remove:$key');
    if (failKey == 'remove:$key') return false;
    values.remove(key);
    return true;
  }

  Future<bool> _set(String key, Object value) async {
    writes.add(key);
    // 模拟 SharedPreferences：写盘失败时，内存值可能已经变化。
    values[key] = value;
    return key != failKey;
  }

  @override
  Future<bool> setString(String key, String value) => _set(key, value);
  @override
  Future<bool> setInt(String key, int value) => _set(key, value);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service extends UpdateService {
  _Service({required super.dio, super.prefs, this.version = '1.0.0'});
  final String version;
  @override
  Future<String> getCurrentVersion() async => version;
}

Map<String, dynamic> _release([String version = 'v1.1.0']) => {
  'tag_name': version,
  'html_url': 'https://github.com/Lingyan000/fluxdo/releases/tag/$version',
};

void main() {
  late _Preferences prefs;
  late Dio dio;
  late List<RequestOptions> requests;
  late List<(int, Object?)> responses;

  setUp(() {
    prefs = _Preferences();
    requests = [];
    responses = [];
    dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            requests.add(request);
            final (status, data) = responses.removeAt(0);
            handler.resolve(
              Response<dynamic>(
                requestOptions: request,
                statusCode: status,
                data: data,
                headers: Headers.fromMap({
                  'etag': ['new-etag'],
                }),
              ),
            );
          },
        ),
      );
  });

  for (final badCache in [null, '{', '{}', 42]) {
    test('304 后无有效缓存时只重取一次：$badCache', () async {
      prefs.values['update_etag'] = 'old-etag';
      if (badCache != null) prefs.values['update_cache'] = badCache;
      prefs.values['update_cache_time'] = 1;
      responses.addAll([(304, null), (200, _release())]);
      final info = await _Service(dio: dio, prefs: prefs).checkForUpdate();
      expect(info.remoteVersion, '1.1.0');
      expect(requests.length, 2);
      expect(requests.first.headers['If-None-Match'], 'old-etag');
      expect(requests.last.headers.containsKey('If-None-Match'), isFalse);
      expect(
        requests.last.uri.path,
        '/repos/Lingyan000/fluxdo/releases/latest',
      );
      expect(prefs.values['update_etag'], 'new-etag');
    });
  }

  test('完整请求再次返回 304 时有界失败', () async {
    responses.addAll([(304, null), (304, null)]);
    await expectLater(
      _Service(dio: dio, prefs: prefs).checkForUpdate(),
      throwsStateError,
    );
    expect(requests.length, 2);
  });

  test('有效的过期缓存可用于 304，并根据当前版本重新计算', () async {
    prefs.values.addAll({
      'update_etag': 'old-etag',
      'update_cache_time': 1,
      'update_cache': jsonEncode(
        UpdateInfo(
          currentVersion: '0.9.0',
          remoteVersion: '1.0.0',
          releaseUrl: 'url',
          releaseNotes: '',
          hasUpdate: true,
        ).toJson(),
      ),
    });
    responses.add((304, null));
    final info = await _Service(dio: dio, prefs: prefs).checkForUpdate();
    expect(info.hasUpdate, isFalse);
    expect(requests.length, 1);
    expect(prefs.values['update_etag'], 'old-etag');
  });

  for (final data in [
    null,
    <String, dynamic>{'tag_name': 42},
  ]) {
    test('解析失败不写 ETag：$data', () async {
      responses.add((200, data));
      await expectLater(
        _Service(dio: dio, prefs: prefs).checkForUpdate(),
        throwsA(anything),
      );
      expect(prefs.writes, isEmpty);
    });
  }

  for (final key in ['update_cache', 'update_cache_time']) {
    test('$key 写盘返回 false 时不保存 ETag', () async {
      prefs.values['update_etag'] = 'old-etag';
      prefs.failKey = key;
      responses.add((200, _release()));
      final info = await _Service(dio: dio, prefs: prefs).checkForUpdate();
      expect(info.hasUpdate, isTrue);
      expect(prefs.values.containsKey('update_etag'), isFalse);
      expect(prefs.writes, isNot(contains('update_etag')));
    });
  }

  test('旧 ETag 清除失败时不替换缓存', () async {
    prefs.failKey = 'remove:update_etag';
    responses.add((200, _release()));
    await _Service(dio: dio, prefs: prefs).checkForUpdate();
    expect(prefs.writes, ['remove:update_etag']);
  });

  test('缓存及时间戳保存成功后才写 ETag', () async {
    responses.add((200, _release()));
    await _Service(dio: dio, prefs: prefs).checkForUpdate();
    expect(prefs.writes, [
      'remove:update_etag',
      'update_cache',
      'update_cache_time',
      'update_etag',
    ]);
  });

  test('200 未提供 ETag 时移除旧关联', () async {
    prefs.values['update_etag'] = 'old-etag';
    dio.interceptors.clear();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          handler.resolve(
            Response<dynamic>(
              requestOptions: request,
              statusCode: 200,
              data: _release(),
            ),
          );
        },
      ),
    );
    await _Service(dio: dio, prefs: prefs).checkForUpdate();
    expect(prefs.values.containsKey('update_etag'), isFalse);
  });
  for (final (current, remote, expected) in [
    ('1.0.0-beta.2', 'v1.0.0-beta.10', true),
    ('1.0.0-beta.10', 'v1.0.0-beta.2', false),
    ('1.0.0-beta.10', 'v1.0.0', true),
    ('1.0.0', 'v1.0.0-beta.10', false),
    ('1.0.0+100', 'v1.0.0+200', false),
    ('1.0.0-beta.2+100', 'v1.0.0-beta.2+200', false),
    ('1.0.0-beta', 'v1.0.0-beta.1', true),
    ('1.0.0-2', 'v1.0.0-beta', true),
    ('1.0.0-beta', 'v1.0.0-2', false),
    ('1.0.0-dev.1', 'v1.0.0-dev.2', true),
    ('0.2.28', 'v0.2.28.1', true),
    ('1.0', 'v1.0.0', false),
  ]) {
    test('版本比较 $current → $remote', () async {
      responses.add((200, _release(remote)));
      final service = _Service(dio: dio, prefs: prefs, version: current);
      final info = await service.checkForUpdate();
      expect(info.hasUpdate, expected);
      expect(info.remoteVersion, remote.substring(1));
      // 自动检查走持久化缓存，也必须使用同样的语义版本比较。
      expect(
        (await service.checkForUpdate(useCache: true)).hasUpdate,
        expected,
      );
      expect(requests.length, 1);
    });
  }
}
