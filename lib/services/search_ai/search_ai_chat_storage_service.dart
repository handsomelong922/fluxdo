import 'dart:convert';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SearchAiChatStorageService {
  SearchAiChatStorageService(this._prefs);

  static const _querySessionsKeyPrefix = 'search_ai_chat_sessions_';
  static const _sessionMessagesKeyPrefix = 'search_ai_chat_messages_';
  static const _allSessionsIndexKey = 'search_ai_chat_all_sessions_index';
  static const _defaultMaxSessions = 80;

  final SharedPreferences _prefs;

  List<AiChatSession> getQuerySessions(String query) {
    final raw = _prefs.getString(_querySessionsKey(query));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((item) => AiChatSession.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  List<AiChatMessage> loadSessionMessages(String sessionId) {
    final raw = _prefs.getString('$_sessionMessagesKeyPrefix$sessionId');
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((item) => AiChatMessage.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveSessionMessages(
    String query,
    String sessionId,
    List<AiChatMessage> messages, {
    String? title,
  }) async {
    final completedMessages = messages
        .where((message) {
          return message.status != MessageStatus.streaming &&
              message.status != MessageStatus.sending;
        })
        .toList(growable: false);

    if (completedMessages.isEmpty) {
      await deleteSession(query, sessionId);
      return;
    }

    await _prefs.setString(
      '$_sessionMessagesKeyPrefix$sessionId',
      jsonEncode(completedMessages.map((message) => message.toJson()).toList()),
    );

    final sessions = getQuerySessions(query).toList();
    final now = DateTime.now();
    final existingIndex = sessions.indexWhere(
      (session) => session.id == sessionId,
    );
    if (existingIndex >= 0) {
      final existing = sessions.removeAt(existingIndex);
      sessions.insert(
        0,
        existing.copyWith(title: title ?? existing.title, updatedAt: now),
      );
    } else {
      sessions.insert(
        0,
        AiChatSession(
          id: sessionId,
          title: title,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    await _saveQuerySessions(query, sessions);
    await _updateGlobalIndex(query, sessionId);
    await _enforceLimit();
  }

  Future<void> deleteSession(String query, String sessionId) async {
    await _prefs.remove('$_sessionMessagesKeyPrefix$sessionId');

    final sessions = getQuerySessions(query).toList()
      ..removeWhere((session) => session.id == sessionId);
    if (sessions.isEmpty) {
      await _prefs.remove(_querySessionsKey(query));
    } else {
      await _saveQuerySessions(query, sessions);
    }

    await _removeFromGlobalIndex(sessionId);
  }

  Future<void> deleteAllQuerySessions(String query) async {
    final sessions = getQuerySessions(query);
    for (final session in sessions) {
      await _prefs.remove('$_sessionMessagesKeyPrefix${session.id}');
      await _removeFromGlobalIndex(session.id);
    }
    await _prefs.remove(_querySessionsKey(query));
  }

  Future<void> _saveQuerySessions(
    String query,
    List<AiChatSession> sessions,
  ) async {
    await _prefs.setString(
      _querySessionsKey(query),
      jsonEncode(sessions.map((session) => session.toJson()).toList()),
    );
  }

  Future<void> _updateGlobalIndex(String query, String sessionId) async {
    final index = _loadGlobalIndex()
      ..removeWhere((item) => item['sessionId'] == sessionId);
    index.insert(0, {
      'query': _normalizeQuery(query),
      'queryKey': _queryKey(query),
      'sessionId': sessionId,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    await _saveGlobalIndex(index);
  }

  Future<void> _removeFromGlobalIndex(String sessionId) async {
    final index = _loadGlobalIndex()
      ..removeWhere((item) => item['sessionId'] == sessionId);
    await _saveGlobalIndex(index);
  }

  List<Map<String, dynamic>> _loadGlobalIndex() {
    final raw = _prefs.getString(_allSessionsIndexKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveGlobalIndex(List<Map<String, dynamic>> index) async {
    await _prefs.setString(_allSessionsIndexKey, jsonEncode(index));
  }

  Future<void> _enforceLimit() async {
    final index = _loadGlobalIndex();
    if (index.length <= _defaultMaxSessions) return;

    final toRemove = index.sublist(_defaultMaxSessions);
    for (final item in toRemove) {
      final query = item['query'] as String? ?? '';
      final sessionId = item['sessionId'] as String? ?? '';
      if (sessionId.isEmpty) continue;
      await _prefs.remove('$_sessionMessagesKeyPrefix$sessionId');

      final sessions = getQuerySessions(query).toList()
        ..removeWhere((session) => session.id == sessionId);
      if (sessions.isEmpty) {
        await _prefs.remove(_querySessionsKey(query));
      } else {
        await _saveQuerySessions(query, sessions);
      }
    }

    await _saveGlobalIndex(index.sublist(0, _defaultMaxSessions));
  }

  String _querySessionsKey(String query) {
    return '$_querySessionsKeyPrefix${_queryKey(query)}';
  }

  static String _queryKey(String query) {
    final bytes = utf8.encode(_normalizeQuery(query).toLowerCase());
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _normalizeQuery(String query) {
    return query.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
