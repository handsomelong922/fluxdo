import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import '../../constants.dart';
import '../../models/topic.dart';
import '../../utils/export_utils.dart';
import 'markdown_to_notion_blocks.dart';
import 'notion_client.dart';
import 'notion_config.dart';

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
  NotionSyncService({required this.config, NotionClient? client})
    : assert(config.isComplete, 'NotionConfig must be complete'),
      _client = client ?? NotionClient(config.integrationToken!);

  static const int _childrenPerRequest = 100;
  static const Duration _requestGap = Duration(milliseconds: 350);

  final NotionConfig config;
  final NotionClient _client;

  Future<NotionSyncResult> syncTopic({
    required TopicDetail detail,
    required NotionSyncScope scope,
    DuplicateAction onDuplicate = DuplicateAction.skip,
    NotionSyncSource source = NotionSyncSource.manualExport,
    Topic? bookmark,
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
      onProgress: (current, total) => onProgress?.call(
        NotionSyncProgress(SyncPhase.fetch, current: current, total: total),
      ),
    );
    if (posts.isEmpty) {
      throw NotionApiException('No posts to sync');
    }

    onProgress?.call(const NotionSyncProgress(SyncPhase.convert));
    final blocks = await _buildBlocks(detail: detail, posts: posts);
    final existingPageId = await _queryTopicPage(detail.id);
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
      ),
      blocks: blocks,
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
    void Function(NotionSyncProgress progress)? onProgress,
  }) async {
    await _ensureDatabaseSchema();
    onProgress?.call(const NotionSyncProgress(SyncPhase.convert));
    final blocks = await _buildBlocks(detail: detail, posts: [post]);
    final existingPageId = await _queryPostPage(detail.id, post.id);
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
    );
    _CreatedPage result;
    try {
      result = await _createPageWithBlocks(
        properties: properties,
        blocks: blocks,
        onProgress: onProgress,
      );
    } on NotionApiException catch (error) {
      if (!_looksLikeMissingProperty(error)) rethrow;
      properties = Map<String, dynamic>.from(properties)..remove('Post ID');
      result = await _createPageWithBlocks(
        properties: properties,
        blocks: blocks,
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

  Future<List<Map<String, dynamic>>> _buildBlocks({
    required TopicDetail detail,
    required List<Post> posts,
  }) async {
    final markdown = await ExportUtils.renderMarkdown(
      detail: detail,
      posts: posts,
    );
    final resolved = _preprocessDiscourseBbcode(
      _resolveUploadShortUrls(markdown, posts),
    );
    final blocks = markdownToNotionBlocks(resolved);
    return blocks.isEmpty
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
  }

  Future<String?> _queryTopicPage(int topicId) async {
    try {
      return await _client.queryPage(config.databaseId!, topicId: topicId);
    } on NotionApiException catch (error) {
      if (_looksLikeMissingProperty(error)) return null;
      rethrow;
    }
  }

  Future<String?> _queryPostPage(int topicId, int postId) async {
    try {
      return await _client.queryPage(
        config.databaseId!,
        topicId: topicId,
        postId: postId,
      );
    } on NotionApiException catch (error) {
      if (!_looksLikeMissingProperty(error)) rethrow;
      return _client.queryPage(config.databaseId!, topicId: topicId);
    }
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
  }) {
    final firstPost = detail.postStream.posts.isEmpty
        ? null
        : detail.postStream.posts.first;
    final author = firstPost?.username ?? '';
    final created = firstPost?.createdAt.toUtc().toIso8601String();
    final url = '${AppConstants.baseUrl}/t/${detail.slug}/${detail.id}';
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
    _addBookmarkProperties(properties, bookmark);
    return properties;
  }

  Map<String, dynamic> _buildPostProperties(
    TopicDetail detail,
    Post post, {
    required NotionSyncSource source,
    Topic? bookmark,
  }) {
    final title =
        '${_truncate(detail.title, 160)} - @${post.username} #${post.postNumber}';
    final url =
        '${AppConstants.baseUrl}/t/${detail.slug}/${detail.id}/${post.postNumber}';
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
    _addBookmarkProperties(properties, bookmark);
    return properties;
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

  String _resolveUploadShortUrls(String markdown, List<Post> posts) {
    final perPostUrls = posts
        .map((post) => _extractCookedImageUrls(post.cooked))
        .toList();
    final segments = markdown.split(RegExp(r'\n---\n'));
    if (segments.length < 2) {
      return _replaceUploadInChunk(
        markdown,
        perPostUrls.expand((e) => e).toList(),
      );
    }
    final output = <String>[segments.first];
    var postIndex = 0;
    for (var i = 1; i < segments.length; i++) {
      final urls = postIndex < perPostUrls.length
          ? perPostUrls[postIndex]
          : const <String>[];
      output.add(_replaceUploadInChunk(segments[i], urls));
      postIndex++;
    }
    return output.join('\n---\n');
  }

  String _replaceUploadInChunk(String chunk, List<String> urls) {
    if (urls.isEmpty || !chunk.contains('upload://')) return chunk;
    final queue = List<String>.from(urls);
    return chunk.replaceAllMapped(RegExp(r'upload://[^\s\)\]<>"]+'), (match) {
      return queue.isEmpty ? match.group(0)! : queue.removeAt(0);
    });
  }

  List<String> _extractCookedImageUrls(String cooked) {
    if (cooked.isEmpty) return const [];
    final fragment = html_parser.parseFragment(cooked);
    final urls = <String>[];
    for (final image in fragment.querySelectorAll('img')) {
      final className = image.attributes['class'] ?? '';
      if (className.contains('emoji')) continue;
      String? source;
      final parent = image.parent;
      if (parent != null && parent.localName == 'a') {
        source = parent.attributes['href'];
      }
      source ??= image.attributes['src'];
      if (source == null || source.isEmpty) continue;
      if (source.startsWith('//')) source = 'https:$source';
      urls.add(source);
    }
    return urls;
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
