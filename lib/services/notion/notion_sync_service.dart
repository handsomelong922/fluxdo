import 'package:flutter/foundation.dart';

import '../../constants.dart';
import '../../models/topic.dart';
import '../../utils/export_utils.dart';
import '../../utils/url_helper.dart';
import '../discourse/discourse_service.dart';
import '../preloaded_data_service.dart';
import 'markdown_to_notion_blocks.dart';
import 'notion_client.dart';
import 'notion_config.dart';
import 'notion_upload_url_resolver.dart';

enum DuplicateAction { skip, overwrite }

enum SyncPhase { fetch, convert, create, append, done }

enum NotionSyncSource {
  manualExport('Manual Export'),
  bookmark('Bookmark');

  const NotionSyncSource(this.label);

  final String label;
}

class NotionSyncProgress {
  const NotionSyncProgress(this.phase, {this.current = 0, this.total = 0});

  final SyncPhase phase;
  final int current;
  final int total;
}

class NotionSyncResult {
  const NotionSyncResult({
    required this.pageId,
    required this.pageUrl,
    required this.postCount,
    required this.duplicated,
  });

  final String pageId;
  final String pageUrl;
  final int postCount;
  final bool duplicated;
}

class NotionSyncService {
  NotionSyncService({
    required this.config,
    NotionClient? client,
    DiscourseService? discourseService,
  }) : assert(config.isComplete, 'NotionConfig must be complete'),
       _client = client ?? NotionClient(config.integrationToken!),
       _discourseService = discourseService ?? DiscourseService();

  static const int _childrenPerRequest = 100;
  static const int _maxDirectUploadBytes = 20 * 1024 * 1024;
  static const Duration _requestGap = Duration(milliseconds: 350);

  final NotionConfig config;
  final NotionClient _client;
  final DiscourseService _discourseService;

  Future<NotionSyncResult> syncTopic({
    required TopicDetail detail,
    required NotionSyncScope scope,
    DuplicateAction onDuplicate = DuplicateAction.skip,
    NotionSyncSource source = NotionSyncSource.manualExport,
    Topic? bookmark,
    bool background = false,
    void Function(NotionSyncProgress progress)? onProgress,
  }) async {
    await _ensureDatabaseSchema();
    final exportScope = scope == NotionSyncScope.firstPostOnly
        ? ExportScope.firstPostOnly
        : ExportScope.allPosts;
    onProgress?.call(const NotionSyncProgress(SyncPhase.fetch));
    final posts = await ExportUtils.fetchPostsForExport(
      detail: detail,
      scope: exportScope,
      background: background,
      onProgress: (current, total) => onProgress?.call(
        NotionSyncProgress(SyncPhase.fetch, current: current, total: total),
      ),
    );
    if (posts.isEmpty) {
      throw NotionApiException('No posts to sync');
    }

    onProgress?.call(const NotionSyncProgress(SyncPhase.convert));
    final content = await _buildContent(
      detail: detail,
      posts: posts,
      background: background,
    );
    final existingPageId = await _queryTopicPage(
      detail.id,
      title: detail.title,
      url: _topicUrl(detail),
    );
    final duplicated = existingPageId != null;
    if (duplicated) {
      if (onDuplicate == DuplicateAction.skip) {
        return NotionSyncResult(
          pageId: existingPageId,
          pageUrl: _pageUrlFromId(existingPageId),
          postCount: posts.length,
          duplicated: true,
        );
      }
      await _archiveIgnoringFailure(existingPageId);
    }

    onProgress?.call(const NotionSyncProgress(SyncPhase.create));
    final result = await _createPageWithBlocks(
      properties: _buildTopicProperties(
        detail,
        source: source,
        bookmark: bookmark,
        attachments: content.attachments,
      ),
      blocks: content.blocks,
      onProgress: onProgress,
    );
    return NotionSyncResult(
      pageId: result.pageId,
      pageUrl: result.pageUrl,
      postCount: posts.length,
      duplicated: duplicated,
    );
  }

  Future<NotionSyncResult> syncPost({
    required TopicDetail detail,
    required Post post,
    DuplicateAction onDuplicate = DuplicateAction.skip,
    NotionSyncSource source = NotionSyncSource.manualExport,
    Topic? bookmark,
    bool background = false,
    void Function(NotionSyncProgress progress)? onProgress,
  }) async {
    await _ensureDatabaseSchema();
    onProgress?.call(const NotionSyncProgress(SyncPhase.convert));
    final content = await _buildContent(
      detail: detail,
      posts: [post],
      background: background,
    );
    final existingPageId = await _queryPostPage(
      detail.id,
      post.id,
      postNumber: post.postNumber,
      title:
          '${_truncate(detail.title, 160)} - @${post.username} #${post.postNumber}',
      url: _postUrl(detail, post.postNumber),
    );
    final duplicated = existingPageId != null;
    if (duplicated) {
      if (onDuplicate == DuplicateAction.skip) {
        return NotionSyncResult(
          pageId: existingPageId,
          pageUrl: _pageUrlFromId(existingPageId),
          postCount: 1,
          duplicated: true,
        );
      }
      await _archiveIgnoringFailure(existingPageId);
    }

    onProgress?.call(const NotionSyncProgress(SyncPhase.create));
    Map<String, dynamic> properties = _buildPostProperties(
      detail,
      post,
      source: source,
      bookmark: bookmark,
      attachments: content.attachments,
    );
    _CreatedPage result;
    try {
      result = await _createPageWithBlocks(
        properties: properties,
        blocks: content.blocks,
        onProgress: onProgress,
      );
    } on NotionApiException catch (error) {
      if (!_looksLikeMissingProperty(error)) rethrow;
      properties = Map<String, dynamic>.from(properties)..remove('Post ID');
      result = await _createPageWithBlocks(
        properties: properties,
        blocks: content.blocks,
        onProgress: onProgress,
      );
    }

    return NotionSyncResult(
      pageId: result.pageId,
      pageUrl: result.pageUrl,
      postCount: 1,
      duplicated: duplicated,
    );
  }

  Future<bool> isDatabaseUpToDate() {
    return _client.hasProperties(
      config.databaseId!,
      notionExportDatabaseProperties().keys,
    );
  }

  Future<void> upgradeDatabase() {
    return _client.ensureProperties(
      config.databaseId!,
      notionExportUpgradeableProperties(),
    );
  }

  Future<String> testConnection() async {
    final data = await _client.retrieveDatabase(config.databaseId!);
    final title = data['title'];
    if (title is! List || title.isEmpty) return '(untitled)';
    final first = title.first;
    if (first is! Map) return '(untitled)';
    return first['plain_text']?.toString() ?? '(untitled)';
  }

  Future<void> ensureDatabaseReadyForSync() => _ensureDatabaseSchema();

  Future<bool> isBookmarkAlreadySynced(Topic bookmark) async {
    final isPost = _isPostBookmark(bookmark);
    final pageId = isPost
        ? await _queryBookmarkPostPage(bookmark)
        : await _queryTopicPage(
            bookmark.id,
            title: bookmark.title,
            url: _bookmarkTopicUrl(bookmark),
          );
    return pageId != null;
  }

  Future<_NotionContent> _buildContent({
    required TopicDetail detail,
    required List<Post> posts,
    bool background = false,
  }) async {
    final markdown = await ExportUtils.renderMarkdown(
      detail: detail,
      posts: posts,
      background: background,
    );
    final resolved = _preprocessDiscourseBbcode(
      await _resolveUploadShortUrls(markdown),
    );
    final uploadedFiles = await _uploadAttachmentFiles(
      resolved,
      background: background,
    );
    final blocks = markdownToNotionBlocks(
      resolved,
      uploadedFiles: uploadedFiles,
    );
    final resolvedBlocks = blocks.isEmpty
        ? [
            {
              'object': 'block',
              'type': 'paragraph',
              'paragraph': {
                'rich_text': [
                  {
                    'type': 'text',
                    'text': {'content': detail.title},
                  },
                ],
              },
            },
          ]
        : blocks;
    return _NotionContent(
      blocks: resolvedBlocks,
      attachments: _dedupeUploadedFiles(uploadedFiles.values),
    );
  }

  Future<String?> _queryTopicPage(
    int topicId, {
    String? title,
    String? url,
  }) async {
    try {
      final byTopicId = await _client.queryPage(
        config.databaseId!,
        topicId: topicId,
      );
      if (byTopicId != null) return byTopicId;
    } on NotionApiException catch (error) {
      if (!_looksLikeMissingProperty(error)) rethrow;
    }
    return _queryByUrlOrTitle(url: url, title: title);
  }

  Future<String?> _queryPostPage(
    int topicId,
    int postId, {
    int? postNumber,
    String? title,
    String? url,
  }) async {
    try {
      final byPostId = await _client.queryPage(
        config.databaseId!,
        topicId: topicId,
        postId: postId,
      );
      if (byPostId != null) return byPostId;
    } on NotionApiException catch (error) {
      if (!_looksLikeMissingProperty(error)) rethrow;
    }
    if (postNumber != null && postNumber > 0) {
      try {
        final byPostNumber = await _client.queryPage(
          config.databaseId!,
          topicId: topicId,
          postNumber: postNumber,
        );
        if (byPostNumber != null) return byPostNumber;
      } on NotionApiException catch (error) {
        if (!_looksLikeMissingProperty(error)) rethrow;
      }
    }
    return _queryByUrlOrTitle(url: url, title: title);
  }

  Future<String?> _queryBookmarkPostPage(Topic bookmark) async {
    final postNumber = bookmark.bookmarkedPostNumber;
    if (postNumber != null && postNumber > 0) {
      try {
        final byPostNumber = await _client.queryPage(
          config.databaseId!,
          topicId: bookmark.id,
          postNumber: postNumber,
        );
        if (byPostNumber != null) return byPostNumber;
      } on NotionApiException catch (error) {
        if (!_looksLikeMissingProperty(error)) rethrow;
      }
    }
    return _queryByUrlOrTitle(url: _bookmarkPostUrl(bookmark), title: null);
  }

  Future<String?> _queryByUrlOrTitle({String? url, String? title}) async {
    if (url != null && url.isNotEmpty) {
      try {
        final byUrl = await _client.queryPageByUrl(config.databaseId!, url);
        if (byUrl != null) return byUrl;
      } on NotionApiException catch (error) {
        if (!_looksLikeMissingProperty(error)) rethrow;
      }
    }
    if (title != null && title.isNotEmpty) {
      try {
        return await _client.queryPageByTitle(config.databaseId!, title);
      } on NotionApiException catch (error) {
        if (!_looksLikeMissingProperty(error)) rethrow;
      }
    }
    return null;
  }

  Future<_CreatedPage> _createPageWithBlocks({
    required Map<String, dynamic> properties,
    required List<Map<String, dynamic>> blocks,
    void Function(NotionSyncProgress progress)? onProgress,
  }) async {
    final firstBatch = blocks.take(_childrenPerRequest).toList();
    final created = await _createPageWithPropertyFallback(
      properties: properties,
      children: firstBatch,
    );
    final pageId = created['id']?.toString();
    if (pageId == null || pageId.isEmpty) {
      throw NotionApiException('No page id in Notion response');
    }
    final pageUrl = created['url']?.toString() ?? _pageUrlFromId(pageId);
    final remaining = blocks.skip(_childrenPerRequest).toList();
    if (remaining.isNotEmpty) {
      final batches = (remaining.length / _childrenPerRequest).ceil();
      for (var i = 0; i < batches; i++) {
        if (i > 0) await Future<void>.delayed(_requestGap);
        final slice = remaining
            .skip(i * _childrenPerRequest)
            .take(_childrenPerRequest)
            .toList();
        onProgress?.call(
          NotionSyncProgress(SyncPhase.append, current: i + 1, total: batches),
        );
        await _client.appendBlockChildren(pageId, slice);
      }
    }
    onProgress?.call(const NotionSyncProgress(SyncPhase.done));
    return _CreatedPage(pageId: pageId, pageUrl: pageUrl);
  }

  Future<Map<String, dynamic>> _createPageWithPropertyFallback({
    required Map<String, dynamic> properties,
    required List<Map<String, dynamic>> children,
  }) async {
    try {
      return await _client.createPage(
        databaseId: config.databaseId!,
        properties: properties,
        children: children,
      );
    } on NotionApiException catch (error) {
      if (!_looksLikeMissingProperty(error)) rethrow;
      final fallback = _legacyCompatibleProperties(properties);
      if (fallback.length == properties.length) rethrow;
      try {
        return await _client.createPage(
          databaseId: config.databaseId!,
          properties: fallback,
          children: children,
        );
      } on NotionApiException catch (secondError) {
        if (!_looksLikeMissingProperty(secondError)) rethrow;
        final minimal = Map<String, dynamic>.from(fallback)..remove('Post ID');
        if (minimal.length == fallback.length) rethrow;
        return _client.createPage(
          databaseId: config.databaseId!,
          properties: minimal,
          children: children,
        );
      }
    }
  }

  Future<void> _ensureDatabaseSchema() async {
    try {
      await upgradeDatabase();
    } catch (error) {
      debugPrint('[NotionSync] ensure database schema failed: $error');
    }
  }

  Future<void> _archiveIgnoringFailure(String pageId) async {
    try {
      await _client.archivePage(pageId);
    } catch (error) {
      debugPrint('[NotionSync] archive old page failed: $error');
    }
  }

  Map<String, dynamic> _buildTopicProperties(
    TopicDetail detail, {
    required NotionSyncSource source,
    Topic? bookmark,
    Iterable<NotionUploadedFile> attachments = const [],
  }) {
    final firstPost = detail.postStream.posts.isEmpty
        ? null
        : detail.postStream.posts.first;
    final author = firstPost?.username ?? '';
    final created = firstPost?.createdAt.toUtc().toIso8601String();
    final url = _topicUrl(detail);
    final properties = <String, dynamic>{
      'Name': {
        'title': [
          {
            'type': 'text',
            'text': {'content': _truncate(detail.title, 200)},
          },
        ],
      },
      'URL': {'url': url},
      'Topic ID': {'number': detail.id},
      'Type': {
        'select': {'name': 'Topic'},
      },
      'Source': {
        'select': {'name': source.label},
      },
      if (detail.categoryId > 0)
        'Category': _richText('Category #${detail.categoryId}'),
      if ((detail.tags ?? const <Tag>[]).isNotEmpty)
        'Tags': {
          'multi_select': detail.tags!
              .map((tag) => {'name': _selectName(tag.name)})
              .toList(),
        },
      if (author.isNotEmpty) 'Author': _richText(author),
      if (created != null)
        'Created': {
          'date': {'start': created},
        },
      'Synced': {
        'date': {'start': DateTime.now().toUtc().toIso8601String()},
      },
    };
    _addAttachmentProperties(properties, attachments);
    _addBookmarkProperties(properties, bookmark);
    return properties;
  }

  Map<String, dynamic> _buildPostProperties(
    TopicDetail detail,
    Post post, {
    required NotionSyncSource source,
    Topic? bookmark,
    Iterable<NotionUploadedFile> attachments = const [],
  }) {
    final title =
        '${_truncate(detail.title, 160)} - @${post.username} #${post.postNumber}';
    final url = _postUrl(detail, post.postNumber);
    final properties = <String, dynamic>{
      'Name': {
        'title': [
          {
            'type': 'text',
            'text': {'content': title},
          },
        ],
      },
      'URL': {'url': url},
      'Topic ID': {'number': detail.id},
      'Post ID': {'number': post.id},
      'Post Number': {'number': post.postNumber},
      'Type': {
        'select': {'name': 'Post'},
      },
      'Source': {
        'select': {'name': source.label},
      },
      if (detail.categoryId > 0)
        'Category': _richText('Category #${detail.categoryId}'),
      if ((detail.tags ?? const <Tag>[]).isNotEmpty)
        'Tags': {
          'multi_select': detail.tags!
              .map((tag) => {'name': _selectName(tag.name)})
              .toList(),
        },
      'Author': _richText(post.username),
      'Created': {
        'date': {'start': post.createdAt.toUtc().toIso8601String()},
      },
      'Synced': {
        'date': {'start': DateTime.now().toUtc().toIso8601String()},
      },
    };
    _addAttachmentProperties(properties, attachments);
    _addBookmarkProperties(properties, bookmark);
    return properties;
  }

  void _addAttachmentProperties(
    Map<String, dynamic> properties,
    Iterable<NotionUploadedFile> attachments,
  ) {
    final files = buildNotionFilesPropertyItems(attachments);
    if (files.isEmpty) return;
    properties['Attachments'] = {'files': files};
  }

  void _addBookmarkProperties(
    Map<String, dynamic> properties,
    Topic? bookmark,
  ) {
    if (bookmark == null) return;
    final bookmarkName = bookmark.bookmarkName?.trim();
    if (bookmark.bookmarkId != null) {
      properties['Bookmark ID'] = {'number': bookmark.bookmarkId};
    }
    if (bookmarkName != null && bookmarkName.isNotEmpty) {
      properties['Bookmark Name'] = _richText(bookmarkName);
    }
    final reminderAt = bookmark.bookmarkReminderAt;
    if (reminderAt != null) {
      properties['Bookmark Reminder'] = {
        'date': {'start': reminderAt.toUtc().toIso8601String()},
      };
    }
    final bookmarkedAt = bookmark.bookmarkCreatedAt;
    if (bookmarkedAt != null) {
      properties['Bookmarked'] = {
        'date': {'start': bookmarkedAt.toUtc().toIso8601String()},
      };
    }
  }

  Map<String, dynamic> _legacyCompatibleProperties(
    Map<String, dynamic> properties,
  ) {
    const allowed = {
      'Name',
      'URL',
      'Topic ID',
      'Post ID',
      'Author',
      'Created',
      'Synced',
    };
    return Map<String, dynamic>.fromEntries(
      properties.entries.where((entry) => allowed.contains(entry.key)),
    );
  }

  bool _looksLikeMissingProperty(NotionApiException error) {
    final message = error.message.toLowerCase();
    return message.contains('post id') ||
        (message.contains('property') && message.contains('not')) ||
        error.code == 'validation_error';
  }

  static String _truncate(String value, int maxLength) {
    return value.length <= maxLength ? value : value.substring(0, maxLength);
  }

  static Map<String, dynamic> _richText(String value) {
    return {
      'rich_text': [
        {
          'type': 'text',
          'text': {'content': _truncate(value, 2000)},
        },
      ],
    };
  }

  static String _selectName(String value) {
    final sanitized = value.replaceAll(',', ' ').trim();
    if (sanitized.isEmpty) return 'untagged';
    return _truncate(sanitized, 100);
  }

  static String _pageUrlFromId(String pageId) {
    return 'https://www.notion.so/${pageId.replaceAll('-', '')}';
  }

  static bool _isPostBookmark(Topic bookmark) {
    return bookmark.bookmarkableType == 'Post' &&
        bookmark.bookmarkedPostNumber != null;
  }

  static String _topicUrl(TopicDetail detail) {
    return '${AppConstants.baseUrl}/t/${detail.slug}/${detail.id}';
  }

  static String _postUrl(TopicDetail detail, int postNumber) {
    return '${_topicUrl(detail)}/$postNumber';
  }

  static String _bookmarkTopicUrl(Topic bookmark) {
    return '${AppConstants.baseUrl}/t/${bookmark.slug}/${bookmark.id}';
  }

  static String? _bookmarkPostUrl(Topic bookmark) {
    final postNumber = bookmark.bookmarkedPostNumber;
    if (postNumber == null || postNumber <= 0) return null;
    return '${_bookmarkTopicUrl(bookmark)}/$postNumber';
  }

  Future<String> _resolveUploadShortUrls(String markdown) async {
    final shortUrls = collectNotionUploadShortUrls(markdown);
    if (shortUrls.isEmpty) return markdown;

    await _discourseService.lookupUrls(shortUrls.toList());
    final resolvedUploads = <String, ResolvedUploadUrl>{};
    for (final shortUrl in shortUrls) {
      final resolved = await _discourseService.resolveShortUpload(shortUrl);
      if (resolved != null && !resolved.isMissing) {
        resolvedUploads[shortUrl] = resolved;
      }
    }

    final secureUploads =
        PreloadedDataService().siteSettingsSync?['secure_uploads'] == true;
    return replaceNotionUploadShortUrls(
      markdown,
      resolvedUploads,
      secureUploads: secureUploads,
    );
  }

  Future<Map<String, NotionUploadedFile>> _uploadAttachmentFiles(
    String markdown, {
    required bool background,
  }) async {
    final attachments = _collectAttachmentLinks(markdown);
    if (attachments.isEmpty) return const {};

    final uploadedFiles = <String, NotionUploadedFile>{};
    for (final attachment in attachments) {
      try {
        final downloaded = await _discourseService.downloadUploadFile(
          attachment.url,
          suggestedFilename: attachment.filename,
          maxBytes: _maxDirectUploadBytes,
          background: background,
        );
        if (downloaded == null) continue;

        final fileUploadId = await _client.uploadSinglePartFile(
          filename: downloaded.filename,
          contentType: downloaded.contentType,
          bytes: downloaded.bytes,
        );
        final uploaded = NotionUploadedFile(
          fileUploadId: fileUploadId,
          filename: downloaded.filename,
          sourceUrl: attachment.normalizedUrl,
        );
        uploadedFiles[attachment.url] = uploaded;
        uploadedFiles[attachment.normalizedUrl] = uploaded;
      } catch (error, stackTrace) {
        debugPrint(
          '[NotionSync] upload attachment failed: '
          '${attachment.url}, error: $error\n$stackTrace',
        );
      }
    }
    return uploadedFiles;
  }

  List<NotionUploadedFile> _dedupeUploadedFiles(
    Iterable<NotionUploadedFile> files,
  ) {
    final result = <NotionUploadedFile>[];
    final seen = <String>{};
    for (final file in files) {
      if (seen.add(file.fileUploadId)) {
        result.add(file);
      }
    }
    return result;
  }

  List<_AttachmentLink> _collectAttachmentLinks(String markdown) {
    final matches = RegExp(
      r'\[([^\]]*\|attachment)\]\(([^)\s]+)(?:\s+"[^"]*")?\)',
    ).allMatches(markdown);
    final result = <_AttachmentLink>[];
    final seen = <String>{};
    for (final match in matches) {
      final label = match.group(1) ?? '';
      final url = match.group(2) ?? '';
      if (url.isEmpty || !seen.add(url)) continue;
      final filename = label.split('|').first.trim();
      result.add(
        _AttachmentLink(
          filename: filename.isEmpty ? 'attachment' : filename,
          url: url,
          normalizedUrl: UrlHelper.resolveUrl(url),
        ),
      );
    }
    return result;
  }

  String _preprocessDiscourseBbcode(String raw) {
    final detailsRegex = RegExp(
      r'\[details(?:=([^\]]*))?\](.*?)\[/details\]',
      dotAll: true,
      caseSensitive: false,
    );
    return raw.replaceAllMapped(detailsRegex, (match) {
      final summary = (match.group(1) ?? 'details').trim();
      final body = (match.group(2) ?? '').trim();
      final quoted = body.split('\n').map((line) => '> $line').join('\n');
      return '> **$summary**\n>\n$quoted';
    });
  }
}

class _CreatedPage {
  const _CreatedPage({required this.pageId, required this.pageUrl});

  final String pageId;
  final String pageUrl;
}

class _NotionContent {
  const _NotionContent({required this.blocks, required this.attachments});

  final List<Map<String, dynamic>> blocks;
  final List<NotionUploadedFile> attachments;
}

@visibleForTesting
List<Map<String, dynamic>> buildNotionFilesPropertyItems(
  Iterable<NotionUploadedFile> attachments,
) {
  return [
    for (final attachment in attachments)
      {
        'name': attachment.filename,
        'type': 'file_upload',
        'file_upload': {'id': attachment.fileUploadId},
      },
  ];
}

class _AttachmentLink {
  const _AttachmentLink({
    required this.filename,
    required this.url,
    required this.normalizedUrl,
  });

  final String filename;
  final String url;
  final String normalizedUrl;
}
