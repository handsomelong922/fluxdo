import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

Map<String, dynamic> notionExportDatabaseProperties() => {
  'Name': {'title': <String, dynamic>{}},
  'URL': {'url': <String, dynamic>{}},
  'Topic ID': {'number': <String, dynamic>{}},
  'Post ID': {'number': <String, dynamic>{}},
  'Post Number': {'number': <String, dynamic>{}},
  'Type': {
    'select': {
      'options': [
        {'name': 'Topic', 'color': 'blue'},
        {'name': 'Post', 'color': 'green'},
      ],
    },
  },
  'Source': {
    'select': {
      'options': [
        {'name': 'Manual Export', 'color': 'gray'},
        {'name': 'Bookmark', 'color': 'purple'},
      ],
    },
  },
  'Category': {'rich_text': <String, dynamic>{}},
  'Tags': {'multi_select': <String, dynamic>{}},
  'Author': {'rich_text': <String, dynamic>{}},
  'Created': {'date': <String, dynamic>{}},
  'Synced': {'date': <String, dynamic>{}},
  'Bookmark ID': {'number': <String, dynamic>{}},
  'Bookmark Name': {'rich_text': <String, dynamic>{}},
  'Bookmark Reminder': {'date': <String, dynamic>{}},
  'Bookmarked': {'date': <String, dynamic>{}},
};

Map<String, dynamic> notionExportUpgradeableProperties() {
  final properties = Map<String, dynamic>.from(
    notionExportDatabaseProperties(),
  );
  properties.remove('Name');
  return properties;
}

class NotionApiException implements Exception {
  NotionApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() =>
      'NotionApiException(${statusCode ?? '-'}${code != null ? '/$code' : ''}): $message';
}

class NotionClient {
  NotionClient(this.token, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.notion.com/v1/',
              headers: {
                'Authorization': 'Bearer $token',
                'Notion-Version': _notionVersion,
                'Content-Type': 'application/json',
              },
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              validateStatus: (_) => true,
            ),
          );

  static const String _notionVersion = '2022-06-28';
  static const String _fileUploadNotionVersion = '2026-03-11';

  final String token;
  final Dio _dio;

  Future<String?> queryPage(
    String databaseId, {
    required int topicId,
    int? postId,
    int? postNumber,
    String topicIdProperty = 'Topic ID',
    String postIdProperty = 'Post ID',
    String postNumberProperty = 'Post Number',
  }) async {
    final filters = <Map<String, dynamic>>[
      {
        'property': topicIdProperty,
        'number': {'equals': topicId},
      },
    ];
    if (postId != null && postId > 0) {
      filters.add({
        'property': postIdProperty,
        'number': {'equals': postId},
      });
    } else if (postNumber != null && postNumber > 0) {
      filters.add({
        'property': postNumberProperty,
        'number': {'equals': postNumber},
      });
    } else {
      filters.add({
        'or': [
          {
            'property': postIdProperty,
            'number': {'is_empty': true},
          },
          {
            'property': postIdProperty,
            'number': {'equals': 0},
          },
        ],
      });
    }

    return _queryFirstPage(databaseId, {
      'filter': {'and': filters},
    });
  }

  Future<String?> queryPageByUrl(String databaseId, String url) {
    return _queryFirstPage(databaseId, {
      'filter': {
        'property': 'URL',
        'url': {'equals': url},
      },
    });
  }

  Future<String?> queryPageByTitle(String databaseId, String title) {
    return _queryFirstPage(databaseId, {
      'filter': {
        'property': 'Name',
        'title': {'equals': title},
      },
    });
  }

  Future<String?> _queryFirstPage(
    String databaseId,
    Map<String, dynamic> query,
  ) async {
    final body = Map<String, dynamic>.from(query)..['page_size'] = 1;
    final data = await _post('databases/$databaseId/query', body);
    final results = data['results'];
    if (results is! List || results.isEmpty) return null;
    final first = results.first;
    if (first is! Map) return null;
    return first['id']?.toString();
  }

  Future<Map<String, dynamic>> createPage({
    required String databaseId,
    required Map<String, dynamic> properties,
    List<Map<String, dynamic>>? children,
  }) {
    return _post(
      'pages',
      {
        'parent': {'database_id': databaseId},
        'properties': properties,
        if (children != null && children.isNotEmpty) 'children': children,
      },
      notionVersion: _containsFileUpload(children)
          ? _fileUploadNotionVersion
          : null,
    );
  }

  Future<Map<String, dynamic>> appendBlockChildren(
    String blockId,
    List<Map<String, dynamic>> children,
  ) {
    return _patch(
      'blocks/$blockId/children',
      {'children': children},
      notionVersion: _containsFileUpload(children)
          ? _fileUploadNotionVersion
          : null,
    );
  }

  Future<Map<String, dynamic>> archivePage(String pageId) {
    return _patch('pages/$pageId', {'archived': true});
  }

  Future<Map<String, dynamic>> createDatabaseForExport({
    required String parentPageId,
    required String title,
  }) {
    return _post('databases', {
      'parent': {'type': 'page_id', 'page_id': parentPageId},
      'title': [
        {
          'type': 'text',
          'text': {'content': title},
        },
      ],
      'properties': notionExportDatabaseProperties(),
    });
  }

  Future<Map<String, dynamic>> retrieveDatabase(String databaseId) {
    return _get('databases/$databaseId');
  }

  Future<String> uploadSinglePartFile({
    required String filename,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final upload = await _post(
      'file_uploads',
      {
        'mode': 'single_part',
        'filename': filename,
        'content_type': contentType,
      },
      notionVersion: _fileUploadNotionVersion,
    );
    final id = upload['id']?.toString();
    if (id == null || id.isEmpty) {
      throw NotionApiException('No file upload id in Notion response');
    }

    final response = await _request(
      () => _dio.post<dynamic>(
        'file_uploads/$id/send',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: filename),
        }),
        options: Options(
          contentType: Headers.multipartFormDataContentType,
          headers: {'Notion-Version': _fileUploadNotionVersion},
        ),
      ),
    );
    final status = response['status']?.toString();
    if (status != null && status != 'uploaded') {
      throw NotionApiException('Notion file upload status is $status');
    }
    return id;
  }

  Future<bool> hasProperty(String databaseId, String propertyName) async {
    final database = await retrieveDatabase(databaseId);
    final properties = database['properties'];
    return properties is Map && properties.containsKey(propertyName);
  }

  Future<bool> hasProperties(
    String databaseId,
    Iterable<String> propertyNames,
  ) async {
    final database = await retrieveDatabase(databaseId);
    final properties = database['properties'];
    if (properties is! Map) return false;
    return propertyNames.every(properties.containsKey);
  }

  Future<void> ensureNumberProperty(
    String databaseId,
    String propertyName,
  ) async {
    if (await hasProperty(databaseId, propertyName)) return;
    await _patch('databases/$databaseId', {
      'properties': {
        propertyName: {'number': {}},
      },
    });
  }

  Future<void> ensureProperties(
    String databaseId,
    Map<String, dynamic> expectedProperties,
  ) async {
    final database = await retrieveDatabase(databaseId);
    final properties = database['properties'];
    final existing = properties is Map
        ? properties.keys.map((key) => key.toString()).toSet()
        : <String>{};
    final missing = <String, dynamic>{};
    for (final entry in expectedProperties.entries) {
      if (!existing.contains(entry.key)) {
        missing[entry.key] = entry.value;
      }
    }
    if (missing.isEmpty) return;
    await _patch('databases/$databaseId', {'properties': missing});
  }

  Future<Map<String, dynamic>> _get(String path) {
    return _request(() => _dio.get<dynamic>(path));
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    String? notionVersion,
  }) {
    return _request(
      () => _dio.post<dynamic>(
        path,
        data: body,
        options: _versionOptions(notionVersion),
      ),
    );
  }

  Future<Map<String, dynamic>> _patch(
    String path,
    Map<String, dynamic> body, {
    String? notionVersion,
  }) {
    return _request(
      () => _dio.patch<dynamic>(
        path,
        data: body,
        options: _versionOptions(notionVersion),
      ),
    );
  }

  Options? _versionOptions(String? notionVersion) {
    if (notionVersion == null) return null;
    return Options(headers: {'Notion-Version': notionVersion});
  }

  Future<Map<String, dynamic>> _request(
    Future<Response<dynamic>> Function() send,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final Response<dynamic> response;
      try {
        response = await send();
      } on DioException catch (error) {
        throw NotionApiException(
          error.message ?? 'network error',
          statusCode: error.response?.statusCode,
        );
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode == 429) {
        final retryAfter = double.tryParse(
          response.headers.value('Retry-After') ?? '',
        );
        final wait = Duration(
          milliseconds: ((retryAfter ?? 1.0 + attempt) * 1000).toInt(),
        );
        debugPrint('[Notion] rate limited, retry in ${wait.inMilliseconds}ms');
        await Future<void>.delayed(wait);
        continue;
      }

      if (statusCode < 200 || statusCode >= 300) {
        final data = response.data;
        var message = 'HTTP $statusCode';
        String? code;
        if (data is Map) {
          message = data['message']?.toString() ?? message;
          code = data['code']?.toString();
        }
        throw NotionApiException(message, statusCode: statusCode, code: code);
      }

      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) {
        return data.map((key, value) => MapEntry('$key', value));
      }
      return <String, dynamic>{};
    }
    throw NotionApiException('Notion API rate-limited too long');
  }

  static bool _containsFileUpload(Object? value) {
    if (value is Map) {
      if (value['type'] == 'file_upload' || value.containsKey('file_upload')) {
        return true;
      }
      return value.values.any(_containsFileUpload);
    }
    if (value is Iterable) {
      return value.any(_containsFileUpload);
    }
    return false;
  }
}
