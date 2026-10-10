import 'dart:async';

import 'topic_regex_rules.dart';

/// 每个列表独立缓存；规则换代会取消旧任务，分页只匹配新增标题。
class TopicRegexFilterController {
  TopicRegexFilterController(this.onChanged);
  final void Function() onChanged;
  final Map<String, bool> matches = {};
  List<String> _patterns = const [];
  List<String> _titles = const [];
  TopicRegexJob? _job;
  Future<void>? _pending;
  int _generation = 0;
  bool _disposed = false;
  FormatException? error;
  bool get isPending => _pending != null;
  bool get active => _patterns.isNotEmpty;

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void prepare(List<String> patterns, Iterable<String> titles) {
    if (_disposed) return;
    final nextTitles = titles.toSet().toList();
    final changed = !_same(patterns, _patterns);
    if (!changed && _same(nextTitles, _titles)) return;
    _generation++;
    _job?.cancel();
    _job = null;
    _pending = null;
    if (changed) {
      matches.clear();
      error = null;
      _patterns = List.of(patterns);
    }
    _titles = nextTitles;
    // 已确认的失败必须用户编辑或显式重试，不能在滚动重建中反复烧 CPU。
    if (patterns.isEmpty || error != null) return;
    final current = nextTitles.toSet();
    matches.removeWhere((title, _) => !current.contains(title));
    if (nextTitles.length > 16384 ||
        nextTitles.fold<int>(0, (sum, title) => sum + title.length) > 4194304) {
      error = const FormatException('titles');
      return;
    }
    final missing = nextTitles
        .where((title) => !matches.containsKey(title))
        .toList();
    if (missing.isEmpty) return;
    final generation = _generation;
    final job = TopicRegexRules.match(patterns, missing);
    _job = job;
    _pending = () async {
      try {
        final result = await job.result;
        if (_disposed || generation != _generation) return;
        for (var i = 0; i < missing.length; i++) {
          matches[missing[i]] = result[i];
        }
      } on FormatException catch (failure) {
        if (_disposed || generation != _generation) return;
        error = failure;
      } catch (_) {
        if (_disposed || generation != _generation) return;
        error = const FormatException('worker');
      } finally {
        if (!_disposed && generation == _generation) {
          _pending = null;
          _job = null;
          onChanged();
        }
      }
    }();
  }

  /// 自动续加载必须等本批匹配结束；失败/取消时停止翻页。
  Future<bool> settle(List<String> patterns, Iterable<String> titles) async {
    prepare(patterns, titles);
    final generation = _generation;
    await _pending;
    return !_disposed && generation == _generation && error == null;
  }

  void retry() {
    if (_disposed) return;
    final patterns = List.of(_patterns);
    final titles = List.of(_titles);
    _titles = const [];
    error = null;
    prepare(patterns, titles);
    onChanged();
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _job?.cancel();
    _job = null;
    _pending = null;
    matches.clear();
  }
}
