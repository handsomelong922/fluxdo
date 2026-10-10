import 'dart:async';
import 'dart:convert';

import 'ai_topic_summary_service.dart';

class TopicSummaryTaskState {
  const TopicSummaryTaskState({this.busy = false, this.progress = '', this.result,
    this.error, this.savedAt});
  final bool busy;
  final String progress;
  final TopicSummaryResult? result;
  final String? error;
  final DateTime? savedAt;
}

/// 后台任务不依赖页面或面板生命周期；每个实例只属于一个账号。
/// 账号切换时销毁实例并取消任务，防止旧任务回写新账号视图。
class AiTopicSummaryTasks {
  AiTopicSummaryTasks({required this.readCache, required this.writeCache});
  final String? Function(String key) readCache;
  final Future<bool> Function(String key, String value) writeCache;
  final _states = <String, TopicSummaryTaskState>{};
  final _running = <String, TopicSummaryCancellation>{};
  final _changes = StreamController<void>.broadcast();
  bool _disposed = false;
  Stream<void> get changes => _changes.stream;

  TopicSummaryTaskState state(String key) {
    if (_disposed) return const TopicSummaryTaskState();
    final value = _states.putIfAbsent(key, () {
      try {
        final raw = readCache(key);
        if (raw == null) return const TopicSummaryTaskState();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (json['version'] != 1) return const TopicSummaryTaskState();
        final text = json['text'] as String;
        final read = json['read'] as int;
        final total = json['total'] as int;
        final missing = (json['missing'] as List).cast<int>();
        if (text.trim().isEmpty || text.length > 6000 || read < 1 || total < read ||
            missing.length != total - read) return const TopicSummaryTaskState();
        return TopicSummaryTaskState(result: TopicSummaryResult(text, read, total, missing),
          savedAt: DateTime.fromMillisecondsSinceEpoch(json['savedAtMillis'] as int));
      } catch (_) {
        return const TopicSummaryTaskState();
      }
    });
    _trim(key);
    return value;
  }

  void _set(String key, TopicSummaryTaskState value) {
    if (_disposed) return;
    _states[key] = value;
    _trim(key);
    _changes.add(null);
  }

  void _trim(String key) {
    // 仅清理已结束的内存快照；运行中的任务继续保留。
    final finished = _states.keys.where((k) => k != key && !_states[k]!.busy).toList();
    while (_states.length > 100 && finished.isNotEmpty) {
      _states.remove(finished.removeAt(0));
    }
  }

  Future<void> start(String key, {
    required Future<AiTopicSummaryService> Function() createService,
    required String prompt,
    bool retry = false,
  }) async {
    if (_disposed || _running.containsKey(key)) return;
    final previous = state(key);
    if (!retry && (previous.result != null || previous.error != null)) return;
    final cancellation = TopicSummaryCancellation();
    _running[key] = cancellation;
    bool current() => !_disposed && identical(_running[key], cancellation) && !cancellation.isCancelled;
    _set(key, TopicSummaryTaskState(busy: true, progress: '正在准备…',
      result: previous.result, savedAt: previous.savedAt));
    try {
      final service = await cancellation.wait(createService());
      cancellation.check();
      final result = await service.summarize(prompt: prompt, cancellation: cancellation,
        onProgress: (progress) {
          if (current()) _set(key, TopicSummaryTaskState(busy: true, progress: progress,
            result: previous.result, savedAt: previous.savedAt));
        });
      if (!current()) return;
      final savedAt = DateTime.now();
      String? warning;
      try {
        final saved = await writeCache(key, jsonEncode({'version': 1, 'text': result.text,
          'read': result.readCount, 'total': result.total, 'missing': result.missingIds,
          'savedAtMillis': savedAt.millisecondsSinceEpoch}));
        if (!saved) warning = '总结已完成，但本地保存失败；本次使用期间仍可查看。';
      } catch (_) {
        warning = '总结已完成，但本地保存失败；本次使用期间仍可查看。';
      }
      if (current()) _set(key, TopicSummaryTaskState(result: result, savedAt: savedAt, error: warning));
    } catch (error) {
      if (current()) _set(key, TopicSummaryTaskState(result: previous.result, savedAt: previous.savedAt,
        error: error is TopicSummaryException ? error.message : '读取或总结失败，请重试或检查模型设置。'));
    } finally {
      if (identical(_running[key], cancellation)) _running.remove(key);
    }
  }

  void cancel(String key) {
    final cancellation = _running.remove(key);
    if (cancellation == null) return;
    cancellation.cancel();
    final old = state(key);
    _set(key, TopicSummaryTaskState(result: old.result, savedAt: old.savedAt, error: '已取消总结'));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final task in _running.values) { task.cancel(); }
    _running.clear();
    _states.clear();
    unawaited(_changes.close());
  }
}
