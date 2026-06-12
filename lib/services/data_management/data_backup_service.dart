import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/s.dart';
import '../storage/resilient_secure_storage.dart';

/// 数据备份导出/导入服务
class DataBackupService {
  static final ResilientSecureStorage _secureStorage = ResilientSecureStorage();
  static const _apiKeyPrefix = 'ai_provider_key_';
  static const _temporaryApiKeyPrefix = 'ai_apikey_';

  /// 需要备份的 key 前缀
  static const _backupKeyPrefixes = [
    'pref_', // 偏好设置
    'ai_', // AI 模型服务配置（API Key 单独从 SecureStorage 导出）
    'theme_', // 主题设置
    'custom_', // 用户自定义屏蔽、AI 提示词等
    'doh_', // DOH 网络设置
    'http_proxy_', // 代理设置
    'upstream_proxy_', // 上游代理协议/加密设置
    'rhttp_', // rhttp 网络引擎设置
    'webview_adapter_', // WebView 网络适配器设置
    'hcaptcha_accessibility_', // hCaptcha 无障碍设置
    'notion_', // Notion 同步配置
    'ldc_reward_', // LDC 打赏凭证
    'topic_sort_', // 话题排序
    'search_', // 搜索设置
  ];

  /// 需要排除的 key 前缀（聊天记录、缓存和运行时状态不备份）
  static const _excludeKeyPrefixes = [
    '__secure_fallback__',
    'ai_chat_session_messages_',
    'ai_chat_topic_sessions_',
    'ai_chat_all_sessions_index',
    'ai_apikey_',
    'search_ai_chat_',
    'sticker_market_index',
    'sticker_market_page_',
    'sticker_market_group_',
    'topic_reading_state_',
    'home_topic_excerpt_cache_',
    'update_cache',
    'update_etag',
    'fingerprint_',
    'ldc_user_info',
    'cdk_user_info',
  ];

  /// 需要备份的完整 key
  static const _backupExactKeys = [
    'seed_color',
    'use_dynamic_color',
    'read_later_items',
    'web_bookmarks',
    'pinned_category_ids',
    'topic_new_subset',
    'auto_check_update',
    'developer_mode',
    'auth_log_enabled',
    'eruda_enabled',
    'cert_use_per_device',
    'ldc_enabled',
    'cdk_enabled',
    'sticker_market_base_url',
    'sticker_subscribed_groups',
  ];

  /// 判断 key 是否应该被备份
  static bool _shouldBackup(String key) {
    // 先检查排除列表
    for (final prefix in _excludeKeyPrefixes) {
      if (key.startsWith(prefix)) return false;
    }
    // 再检查前缀匹配
    for (final prefix in _backupKeyPrefixes) {
      if (key.startsWith(prefix)) return true;
    }
    return _backupExactKeys.contains(key);
  }

  /// 导出数据为 Map
  static Future<Map<String, dynamic>> exportData(
    SharedPreferences prefs,
  ) async {
    final pkg = await PackageInfo.fromPlatform();
    final data = <String, Map<String, dynamic>>{};

    for (final key in prefs.getKeys()) {
      if (!_shouldBackup(key)) continue;

      final value = prefs.get(key);
      if (value == null) continue;

      String type;
      dynamic serializedValue;

      if (value is bool) {
        type = 'bool';
        serializedValue = value;
      } else if (value is int) {
        type = 'int';
        serializedValue = value;
      } else if (value is double) {
        type = 'double';
        serializedValue = value;
      } else if (value is String) {
        type = 'String';
        serializedValue = value;
      } else if (value is List<String>) {
        type = 'StringList';
        serializedValue = value;
      } else {
        continue;
      }

      data[key] = {'type': type, 'value': serializedValue};
    }

    // 导出 AI 供应商 API Key（存储在 FlutterSecureStorage 中）
    final apiKeys = await _exportApiKeys(prefs);

    return {
      'version': 1,
      'appVersion': pkg.version,
      'exportTime': DateTime.now().toIso8601String(),
      'data': data,
      if (apiKeys.isNotEmpty) 'apiKeys': apiKeys,
    };
  }

  /// 从 SecureStorage 中导出所有 AI 供应商的 API Key
  static Future<Map<String, String>> _exportApiKeys(
    SharedPreferences prefs,
  ) async {
    final apiKeys = <String, String>{};
    final providersJson = prefs.getString('ai_providers');
    if (providersJson == null) return apiKeys;

    try {
      final list = jsonDecode(providersJson) as List<dynamic>;
      for (final item in list) {
        final id = (item as Map<String, dynamic>)['id'] as String?;
        if (id == null) continue;
        final secureKey = await _secureStorage.read(key: '$_apiKeyPrefix$id');
        final temporaryKey = prefs
            .getString('$_temporaryApiKeyPrefix$id')
            ?.trim();
        final key =
            secureKey ??
            (temporaryKey != null && temporaryKey.isNotEmpty
                ? temporaryKey
                : null);
        if (key != null && key.isNotEmpty) {
          apiKeys[id] = key;
        }
      }
    } catch (_) {
      // 解析失败时跳过
    }
    return apiKeys;
  }

  /// 将导出数据写入临时文件，返回文件路径
  static Future<String> exportToFile(SharedPreferences prefs) async {
    final exportData = await DataBackupService.exportData(prefs);
    final jsonStr = const JsonEncoder.withIndent('  ').convert(exportData);

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${tempDir.path}/fluxdo_backup_$timestamp.json');
    await file.writeAsString(jsonStr);

    return file.path;
  }

  /// 从 Map 导入数据
  static Future<void> importData(
    SharedPreferences prefs,
    Map<String, dynamic> backup,
  ) async {
    final data = backup['data'] as Map<String, dynamic>?;
    if (data == null) throw FormatException(S.current.backup_missingDataField);

    for (final entry in data.entries) {
      final key = entry.key;
      final item = entry.value as Map<String, dynamic>;
      final type = item['type'] as String;
      final value = item['value'];

      switch (type) {
        case 'bool':
          await prefs.setBool(key, value as bool);
        case 'int':
          await prefs.setInt(key, value as int);
        case 'double':
          await prefs.setDouble(key, (value as num).toDouble());
        case 'String':
          await prefs.setString(key, value as String);
        case 'StringList':
          await prefs.setStringList(
            key,
            (value as List<dynamic>).cast<String>(),
          );
      }
    }

    // 导入 API Key 到 SecureStorage
    final apiKeys = backup['apiKeys'] as Map<String, dynamic>?;
    if (apiKeys != null) {
      for (final entry in apiKeys.entries) {
        await _secureStorage.write(
          key: '$_apiKeyPrefix${entry.key}',
          value: entry.value as String,
        );
        await prefs.remove('$_temporaryApiKeyPrefix${entry.key}');
      }
    }
  }

  /// 从文件路径读取并解析备份数据
  static Future<Map<String, dynamic>> parseBackupFile(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;

    // 基本校验
    if (json['version'] == null || json['data'] == null) {
      throw FormatException(S.current.backup_invalidFormat);
    }

    return json;
  }
}
