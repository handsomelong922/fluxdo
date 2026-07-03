import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/theme_provider.dart';
import '../utils/time_utils.dart';

class TopicReadingState {
  const TopicReadingState({
    required this.topicId,
    required this.postNumber,
    required this.nestedView,
    required this.updatedAt,
  });

  final int topicId;
  final int postNumber;
  final bool nestedView;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'topic_id': topicId,
      'post_number': postNumber,
      'nested_view': nestedView,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  static TopicReadingState? fromJson(Map<String, dynamic> json) {
    final topicId = json['topic_id'] as int?;
    final postNumber = json['post_number'] as int?;
    final nestedView = json['nested_view'] as bool?;
    final updatedAt = TimeUtils.parseUtcTime(json['updated_at'] as String?);
    if (topicId == null ||
        postNumber == null ||
        postNumber <= 0 ||
        nestedView == null ||
        updatedAt == null) {
      return null;
    }
    return TopicReadingState(
      topicId: topicId,
      postNumber: postNumber,
      nestedView: nestedView,
      updatedAt: updatedAt,
    );
  }
}

class TopicReadingStateService {
  TopicReadingStateService(
    this._prefs, {
    this.saveDebounce = const Duration(milliseconds: 400),
  });

  static const _keyPrefix = 'topic_reading_state_';
  static const _maxAge = Duration(days: 30);

  final SharedPreferences _prefs;
  final Duration saveDebounce;
  final Map<int, TopicReadingState> _pendingStates = {};
  final Map<int, Timer> _saveTimers = {};

  TopicReadingState? getState(int topicId) {
    final pending = _pendingStates[topicId];
    if (pending != null) return pending;

    final raw = _prefs.getString('$_keyPrefix$topicId');
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final state = TopicReadingState.fromJson(json);
      if (state == null) return null;
      if (DateTime.now().difference(state.updatedAt) > _maxAge) {
        _prefs.remove('$_keyPrefix$topicId');
        return null;
      }
      return state;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveState({
    required int topicId,
    required int postNumber,
    required bool nestedView,
  }) async {
    if (postNumber <= 0) return;
    final state = TopicReadingState(
      topicId: topicId,
      postNumber: postNumber,
      nestedView: nestedView,
      updatedAt: DateTime.now(),
    );
    _pendingStates[topicId] = state;

    final existingTimer = _saveTimers.remove(topicId);
    existingTimer?.cancel();

    if (saveDebounce == Duration.zero) {
      await _persistState(topicId, state);
      return;
    }

    _saveTimers[topicId] = Timer(saveDebounce, () {
      final latest = _pendingStates[topicId];
      if (latest == null) return;
      unawaited(_persistState(topicId, latest));
    });
  }

  Future<void> clearState(int topicId) async {
    _saveTimers.remove(topicId)?.cancel();
    _pendingStates.remove(topicId);
    await _prefs.remove('$_keyPrefix$topicId');
  }

  Future<void> _persistState(int topicId, TopicReadingState state) async {
    final latest = _pendingStates[topicId];
    if (latest != state) return;
    _saveTimers.remove(topicId);
    await _prefs.setString('$_keyPrefix$topicId', jsonEncode(state.toJson()));
    if (_pendingStates[topicId] == state) {
      _pendingStates.remove(topicId);
    }
  }

  @visibleForTesting
  Future<void> flushPendingWrites() async {
    final topicIds = _pendingStates.keys.toList(growable: false);
    for (final topicId in topicIds) {
      _saveTimers.remove(topicId)?.cancel();
      final state = _pendingStates[topicId];
      if (state != null) {
        await _persistState(topicId, state);
      }
    }
  }
}

final topicReadingStateServiceProvider = Provider<TopicReadingStateService>(
  (ref) => TopicReadingStateService(ref.watch(sharedPreferencesProvider)),
);
