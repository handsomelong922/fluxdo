import 'dart:collection';

import 'package:flutter/foundation.dart';

/// 记录当前进程启动后的网络请求，用于在日志页查看首屏请求耗时排序。
class StartupRequestRecorder extends ChangeNotifier {
  StartupRequestRecorder._() : processStartedAt = DateTime.now();

  static final StartupRequestRecorder instance = StartupRequestRecorder._();
  static const int _maxRecords = 300;

  static StartupRequestRecorder ensureInitialized() => instance;

  final DateTime processStartedAt;
  final ListQueue<StartupRequestRecord> _records =
      ListQueue<StartupRequestRecord>();
  int _nextSequence = 0;

  List<StartupRequestRecord> get records =>
      List.unmodifiable(_records.toList(growable: false));

  List<StartupRequestRecord> get recordsByDuration {
    final sorted = _records.toList(growable: false);
    sorted.sort((left, right) {
      final durationCompare = right.durationMs.compareTo(left.durationMs);
      if (durationCompare != 0) return durationCompare;
      return left.sequence.compareTo(right.sequence);
    });
    return List.unmodifiable(sorted);
  }

  int get sessionAgeMs =>
      DateTime.now().difference(processStartedAt).inMilliseconds;

  StartupRequestRecord record({
    required int? startedAtMillis,
    required int? durationMs,
    required String method,
    required String url,
    required String path,
    required int? statusCode,
    required String level,
    required String? priority,
    required bool isSilent,
    required String? networkAdapter,
    required String? errorType,
  }) {
    final startedAt = startedAtMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(startedAtMillis)
        : DateTime.now();
    final entry = StartupRequestRecord(
      sequence: _nextSequence++,
      timestamp: DateTime.now(),
      relativeStartMs: startedAt.difference(processStartedAt).inMilliseconds,
      durationMs: durationMs ?? 0,
      method: method,
      url: url,
      path: path,
      statusCode: statusCode,
      level: level,
      priority: priority,
      isSilent: isSilent,
      networkAdapter: networkAdapter,
      errorType: errorType,
    );

    _records.add(entry);
    while (_records.length > _maxRecords) {
      _records.removeFirst();
    }
    notifyListeners();
    return entry;
  }

  void clear() {
    _records.clear();
    notifyListeners();
  }
}

@immutable
class StartupRequestRecord {
  const StartupRequestRecord({
    required this.sequence,
    required this.timestamp,
    required this.relativeStartMs,
    required this.durationMs,
    required this.method,
    required this.url,
    required this.path,
    required this.statusCode,
    required this.level,
    required this.priority,
    required this.isSilent,
    required this.networkAdapter,
    required this.errorType,
  });

  final int sequence;
  final DateTime timestamp;
  final int relativeStartMs;
  final int durationMs;
  final String method;
  final String url;
  final String path;
  final int? statusCode;
  final String level;
  final String? priority;
  final bool isSilent;
  final String? networkAdapter;
  final String? errorType;

  String toSummaryLine() {
    final parts = <String>[
      '${durationMs}ms',
      '+${relativeStartMs}ms',
      method,
      path,
      if (statusCode != null) '$statusCode',
      if (priority != null) 'priority=$priority',
      if (isSilent) 'silent',
      if (networkAdapter != null) 'adapter=$networkAdapter',
      if (errorType != null) 'error=$errorType',
    ];
    return parts.join(' · ');
  }
}
