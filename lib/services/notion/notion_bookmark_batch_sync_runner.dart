import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../l10n/s.dart';
import '../toast_service.dart';
import 'notion_bookmark_batch_sync.dart';
import 'notion_client.dart';
import 'notion_config.dart';

enum NotionBookmarkBatchRunStatus { idle, running, completed, failed }

class NotionBookmarkBatchRunState {
  const NotionBookmarkBatchRunState({
    required this.status,
    this.progress,
    this.result,
    this.error,
  });

  const NotionBookmarkBatchRunState.idle()
    : status = NotionBookmarkBatchRunStatus.idle,
      progress = null,
      result = null,
      error = null;

  const NotionBookmarkBatchRunState.running({this.progress})
    : status = NotionBookmarkBatchRunStatus.running,
      result = null,
      error = null;

  const NotionBookmarkBatchRunState.completed(this.result)
    : status = NotionBookmarkBatchRunStatus.completed,
      progress = const NotionBookmarkBatchProgress(
        phase: NotionBookmarkBatchPhase.done,
      ),
      error = null;

  const NotionBookmarkBatchRunState.failed(this.error)
    : status = NotionBookmarkBatchRunStatus.failed,
      progress = null,
      result = null;

  final NotionBookmarkBatchRunStatus status;
  final NotionBookmarkBatchProgress? progress;
  final NotionBookmarkBatchResult? result;
  final Object? error;

  bool get isRunning => status == NotionBookmarkBatchRunStatus.running;
}

class NotionBookmarkBatchSyncRunner {
  NotionBookmarkBatchSyncRunner._();

  static final NotionBookmarkBatchSyncRunner instance =
      NotionBookmarkBatchSyncRunner._();

  final ValueNotifier<NotionBookmarkBatchRunState> state =
      ValueNotifier<NotionBookmarkBatchRunState>(
        const NotionBookmarkBatchRunState.idle(),
      );

  Future<void>? _activeTask;

  bool get isRunning => state.value.isRunning;

  void start(NotionConfig config) {
    if (!config.isComplete) return;
    if (isRunning) {
      ToastService.show(S.current.notion_syncing);
      return;
    }

    state.value = const NotionBookmarkBatchRunState.running();
    ToastService.show(S.current.notion_syncing);
    final task = _run(config);
    _activeTask = task;
    unawaited(task);
  }

  Future<void> waitForIdle() async {
    await _activeTask;
  }

  Future<void> _run(NotionConfig config) async {
    try {
      final result = await NotionBookmarkBatchSync(config: config).syncAll(
        onProgress: (progress) {
          state.value = NotionBookmarkBatchRunState.running(progress: progress);
        },
      );
      state.value = NotionBookmarkBatchRunState.completed(result);
      if (result.total == 0) {
        ToastService.show(S.current.notion_historySyncEmpty);
      } else {
        ToastService.showSuccess(
          S.current.notion_historySyncDone(
            result.success,
            result.skipped,
            result.failed,
          ),
        );
      }
    } on NotionApiException catch (error) {
      state.value = NotionBookmarkBatchRunState.failed(error);
      ToastService.showError(S.current.notion_historySyncFailed(error.message));
    } catch (error, stackTrace) {
      debugPrint('[NotionBookmarkBatchSyncRunner] failed: $error\n$stackTrace');
      state.value = NotionBookmarkBatchRunState.failed(error);
      ToastService.showError(
        S.current.notion_historySyncFailed(error.toString()),
      );
    } finally {
      _activeTask = null;
    }
  }
}
