import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../models/export_history_item.dart';
import '../../models/topic.dart';
import '../../providers/export_history_provider.dart';
import '../../providers/notion_config_provider.dart';
import '../../services/discourse/discourse_service.dart';
import '../../services/toast_service.dart';
import '../../utils/export_utils.dart';
import '../../utils/share_utils.dart';
import 'notion_client.dart';
import 'notion_config.dart';
import 'notion_sync_service.dart';

class NotionBookmarkAutoSync {
  NotionBookmarkAutoSync._();

  static Future<void> tryTriggerTopic({
    required WidgetRef ref,
    required int topicId,
  }) async {
    final config = await _resolveActiveConfig(ref);
    if (config == null) return;
    unawaited(_runTopic(ref: ref, topicId: topicId, config: config));
  }

  static Future<void> tryTriggerPost({
    required WidgetRef ref,
    required int topicId,
    required int postId,
  }) async {
    final config = await _resolveActiveConfig(ref);
    if (config == null) return;
    unawaited(
      _runPost(ref: ref, topicId: topicId, postId: postId, config: config),
    );
  }

  static Future<NotionConfig?> _resolveActiveConfig(WidgetRef ref) async {
    await ref.read(notionConfigProvider.notifier).ensureLoaded();
    final config = ref.read(notionConfigProvider);
    if (!config.autoSyncOnBookmark || !config.isComplete) return null;
    return config;
  }

  static Future<void> _runTopic({
    required WidgetRef ref,
    required int topicId,
    required NotionConfig config,
  }) async {
    final handle = ToastService.showDownload(S.current.notion_syncing);
    handle.updateProgress(-1);
    try {
      final detail = await DiscourseService().getTopicDetail(topicId);
      handle.updateFileName(detail.title);
      final service = NotionSyncService(config: config);
      final result = await service.syncTopic(
        detail: detail,
        scope: config.syncScope,
        onDuplicate: DuplicateAction.skip,
        source: NotionSyncSource.bookmark,
        onProgress: (progress) {
          handle.updateFileName(_progressLabel(detail.title, progress));
          handle.updateProgress(
            progress.total > 0 ? progress.current / progress.total : -1,
          );
        },
      );
      ref
          .read(exportHistoryProvider.notifier)
          .add(
            _historyItem(
              detail: detail,
              title: detail.title,
              scope: config.syncScope == NotionSyncScope.firstPostOnly
                  ? ExportScope.firstPostOnly
                  : ExportScope.allPosts,
              pageUrl: result.pageUrl,
              postCount: result.postCount,
            ),
          );
      handle.dismiss();
      ToastService.showSuccess(S.current.notion_syncSucceed);
    } on NotionApiException catch (error) {
      handle.dismiss();
      ToastService.showError(S.current.notion_syncFailed(error.message));
    } catch (error, stackTrace) {
      debugPrint('[NotionAutoSync] topic failed: $error\n$stackTrace');
      handle.dismiss();
      ToastService.showError(S.current.notion_syncFailed(error.toString()));
    }
  }

  static Future<void> _runPost({
    required WidgetRef ref,
    required int topicId,
    required int postId,
    required NotionConfig config,
  }) async {
    final handle = ToastService.showDownload(S.current.notion_syncing);
    handle.updateProgress(-1);
    try {
      final detail = await DiscourseService().getTopicDetail(topicId);
      final post = _findPost(detail, postId);
      if (post == null) {
        throw NotionApiException('post #$postId not found in topic detail');
      }
      final title = '${detail.title} - @${post.username} #${post.postNumber}';
      handle.updateFileName(title);
      final service = NotionSyncService(config: config);
      final result = await service.syncPost(
        detail: detail,
        post: post,
        onDuplicate: DuplicateAction.skip,
        source: NotionSyncSource.bookmark,
        onProgress: (progress) {
          handle.updateFileName(_progressLabel(title, progress));
          handle.updateProgress(
            progress.total > 0 ? progress.current / progress.total : -1,
          );
        },
      );
      ref
          .read(exportHistoryProvider.notifier)
          .add(
            _historyItem(
              detail: detail,
              title: title,
              scope: ExportScope.firstPostOnly,
              pageUrl: result.pageUrl,
              postCount: 1,
            ),
          );
      handle.dismiss();
      ToastService.showSuccess(S.current.notion_syncSucceed);
    } on NotionApiException catch (error) {
      handle.dismiss();
      ToastService.showError(S.current.notion_syncFailed(error.message));
    } catch (error, stackTrace) {
      debugPrint('[NotionAutoSync] post failed: $error\n$stackTrace');
      handle.dismiss();
      ToastService.showError(S.current.notion_syncFailed(error.toString()));
    }
  }

  static Post? _findPost(TopicDetail detail, int postId) {
    for (final post in detail.postStream.posts) {
      if (post.id == postId) return post;
    }
    return null;
  }

  static ExportHistoryItem _historyItem({
    required TopicDetail detail,
    required String title,
    required ExportScope scope,
    required String pageUrl,
    required int postCount,
  }) {
    final createdAt = DateTime.now();
    return ExportHistoryItem(
      id: '${createdAt.millisecondsSinceEpoch}-${detail.id}-notion',
      topicId: detail.id,
      topicTitle: title,
      topicSlug: detail.slug,
      format: ExportFormat.notion,
      scope: scope,
      postCount: postCount,
      byteSize: 0,
      destination: ShareOutcomeType.notion,
      createdAtMillis: createdAt.millisecondsSinceEpoch,
      filePath: pageUrl,
    );
  }

  static String _progressLabel(String title, NotionSyncProgress progress) {
    final prefix = title.length > 30 ? '${title.substring(0, 30)}...' : title;
    return '$prefix - ${_phaseLabel(progress)}';
  }

  static String _phaseLabel(NotionSyncProgress progress) {
    switch (progress.phase) {
      case SyncPhase.fetch:
        return progress.total > 0
            ? S.current.notion_syncingFetch(progress.current, progress.total)
            : S.current.notion_syncing;
      case SyncPhase.convert:
        return S.current.notion_syncingConvert;
      case SyncPhase.create:
        return S.current.notion_syncingCreate;
      case SyncPhase.append:
        return S.current.notion_syncingAppend(progress.current, progress.total);
      case SyncPhase.done:
        return S.current.notion_syncing;
    }
  }
}
