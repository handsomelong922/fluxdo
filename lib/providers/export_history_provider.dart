import 'dart:convert';

// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/export_history_item.dart';
import 'core_providers.dart';

const int maxExportHistoryItems = 200;

String _sanitizeExportHistoryAccount(String? username) {
  final value = username?.trim();
  if (value == null || value.isEmpty) return 'anonymous';
  return value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_');
}

class ExportHistoryNotifier extends StateNotifier<List<ExportHistoryItem>> {
  ExportHistoryNotifier(this._prefs, this._storageKey)
      : super(_load(_prefs, _storageKey));

  final SharedPreferences _prefs;
  final String _storageKey;

  static List<ExportHistoryItem> _load(
    SharedPreferences prefs,
    String storageKey,
  ) {
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((item) => item.map(
                (key, value) => MapEntry(key.toString(), value),
              ))
          .map(ExportHistoryItem.fromJson)
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  void add(ExportHistoryItem item) {
    final list = state.where((existing) => existing.id != item.id).toList();
    list.insert(0, item);
    state = list.length > maxExportHistoryItems
        ? list.sublist(0, maxExportHistoryItems)
        : list;
    _save();
  }

  void remove(String id) {
    state = state.where((item) => item.id != id).toList(growable: false);
    _save();
  }

  void clearAll() {
    state = const [];
    _save();
  }

  void _save() {
    final raw = jsonEncode(state.map((item) => item.toJson()).toList());
    _prefs.setString(_storageKey, raw);
  }
}

final exportHistoryProvider =
    StateNotifierProvider<ExportHistoryNotifier, List<ExportHistoryItem>>(
  (ref) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final username = ref.watch(
      currentUserProvider.select((value) => value.value?.username),
    );
    final account = _sanitizeExportHistoryAccount(username);
    return ExportHistoryNotifier(prefs, 'export_history_$account');
  },
);
