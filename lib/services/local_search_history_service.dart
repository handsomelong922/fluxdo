import 'package:shared_preferences/shared_preferences.dart';

List<String> mergeLocalSearchHistory({
  required Iterable<String> existing,
  required String query,
  required int maxEntries,
}) {
  if (maxEntries <= 0) return const [];

  final merged = <String>[];
  final normalizedKeys = <String>{};

  void add(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    if (!normalizedKeys.add(normalized.toLowerCase())) return;
    merged.add(normalized);
  }

  add(query);
  for (final entry in existing) {
    add(entry);
    if (merged.length >= maxEntries) break;
  }

  return merged.take(maxEntries).toList(growable: false);
}

class LocalSearchHistoryService {
  LocalSearchHistoryService(this._prefs, {this.maxEntries = 10});

  static const storageKey = 'search_recent_queries_v1';

  final SharedPreferences _prefs;
  final int maxEntries;

  List<String> load() {
    return mergeLocalSearchHistory(
      existing: _prefs.getStringList(storageKey) ?? const [],
      query: '',
      maxEntries: maxEntries,
    );
  }

  Future<void> save(Iterable<String> entries) async {
    final normalized = mergeLocalSearchHistory(
      existing: entries,
      query: '',
      maxEntries: maxEntries,
    );
    await _prefs.setStringList(storageKey, normalized);
  }

  Future<void> clear() async {
    await _prefs.remove(storageKey);
  }
}
