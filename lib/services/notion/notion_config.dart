import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum NotionSyncScope {
  firstPostOnly('first_post_only'),
  allPosts('all_posts');

  const NotionSyncScope(this.code);

  final String code;

  static NotionSyncScope fromCode(String? code) {
    return values.firstWhere(
      (scope) => scope.code == code,
      orElse: () => NotionSyncScope.allPosts,
    );
  }
}

class NotionConfig {
  const NotionConfig({
    this.integrationToken,
    this.databaseId,
    this.autoSyncOnBookmark = false,
    this.syncScope = NotionSyncScope.allPosts,
  });

  final String? integrationToken;
  final String? databaseId;
  final bool autoSyncOnBookmark;
  final NotionSyncScope syncScope;

  bool get isComplete =>
      integrationToken != null &&
      integrationToken!.trim().isNotEmpty &&
      databaseId != null &&
      databaseId!.trim().isNotEmpty;

  bool get hasStoredValues =>
      (integrationToken ?? '').trim().isNotEmpty ||
      (databaseId ?? '').trim().isNotEmpty ||
      autoSyncOnBookmark ||
      syncScope != NotionSyncScope.allPosts;

  NotionConfig copyWith({
    String? integrationToken,
    String? databaseId,
    bool? autoSyncOnBookmark,
    NotionSyncScope? syncScope,
    bool clearToken = false,
    bool clearDatabaseId = false,
  }) {
    return NotionConfig(
      integrationToken: clearToken
          ? null
          : (integrationToken ?? this.integrationToken),
      databaseId: clearDatabaseId ? null : (databaseId ?? this.databaseId),
      autoSyncOnBookmark: autoSyncOnBookmark ?? this.autoSyncOnBookmark,
      syncScope: syncScope ?? this.syncScope,
    );
  }

  Map<String, dynamic> toJson() => {
    if (integrationToken != null) 'token': integrationToken,
    if (databaseId != null) 'database_id': databaseId,
    'auto_sync_bookmark': autoSyncOnBookmark,
    'sync_scope': syncScope.code,
  };

  factory NotionConfig.fromJson(Map<String, dynamic> json) {
    return NotionConfig(
      integrationToken: json['token']?.toString(),
      databaseId: json['database_id']?.toString(),
      autoSyncOnBookmark: json['auto_sync_bookmark'] as bool? ?? false,
      syncScope: NotionSyncScope.fromCode(json['sync_scope']?.toString()),
    );
  }
}

class NotionConfigRepository {
  NotionConfigRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String _keyPrefix = 'notion_config_';
  static const String fallbackAccountId = 'default';
  static const String _lastAccountKey = 'notion_config_last_account';

  String _key(String accountId) {
    final sanitized = accountId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_');
    return '$_keyPrefix$sanitized';
  }

  NotionConfig read(String accountId) {
    final raw = _prefs.getString(_key(accountId));
    if (raw == null || raw.isEmpty) return const NotionConfig();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const NotionConfig();
      final json = decoded.map((key, value) => MapEntry('$key', value));
      return NotionConfig.fromJson(json);
    } catch (_) {
      return const NotionConfig();
    }
  }

  NotionConfig readFallback() {
    final lastAccountId = _prefs.getString(_lastAccountKey);
    if (lastAccountId != null && lastAccountId.isNotEmpty) {
      final config = read(lastAccountId);
      if (config.hasStoredValues) return config;
    }
    return read(fallbackAccountId);
  }

  Future<void> write(String accountId, NotionConfig config) async {
    await _prefs.setString(_key(accountId), jsonEncode(config.toJson()));
    if (accountId != fallbackAccountId) {
      await _prefs.setString(_lastAccountKey, accountId);
    }
  }

  Future<void> clear(String accountId) async {
    await _prefs.remove(_key(accountId));
    if (_prefs.getString(_lastAccountKey) == accountId) {
      await _prefs.remove(_lastAccountKey);
    }
  }

  Future<void> clearFallbackSources() async {
    final lastAccountId = _prefs.getString(_lastAccountKey);
    await clear(fallbackAccountId);
    if (lastAccountId != null && lastAccountId.isNotEmpty) {
      await clear(lastAccountId);
    }
    await _prefs.remove(_lastAccountKey);
  }
}
