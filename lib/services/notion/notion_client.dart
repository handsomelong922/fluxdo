import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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

  final String token;
  final Dio _dio;

  Future<String?> queryPage(
    String databaseId, {
    required int topicId,
    int? postId,
    String topicIdProperty = 'Topic ID',
    String postIdProperty = 'Post ID',
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

    final data = await _post('databases/$databaseId/query', {
      'filter': {'and': filters},
      'page_size': 1,
    });
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
    return _post('pages', {
      'parent': {'database_id': databaseId},
      'properties': properties,
      if (children != null && children.isNotEmpty) 'children': children,
    });
  }

  Future<Map<String, dynamic>> appendBlockChildren(
    String blockId,
    List<Map<String, dynamic>> children,
  ) {
    return _patch('blocks/$blockId/children', {'children': children});
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
      'properties': {
        'Name': {'title': {}},
        'URL': {'url': {}},
        'Topic ID': {'number': {}},
        'Post ID': {'number': {}},
        'Author': {'rich_text': {}},
        'Created': {'date': {}},
        'Synced': {'date': {}},
      },
    });
  }

  Future<Map<String, dynamic>> retrieveDatabase(String databaseId) {
    return _get('databases/$databaseId');
  }

  Future<bool> hasProperty(String databaseId, String propertyName) async {
    final database = await retrieveDatabase(databaseId);
    final properties = database['properties'];
    return properties is Map && properties.containsKey(propertyName);
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

  Future<Map<String, dynamic>> _get(String path) {
    return _request(() => _dio.get<dynamic>(path));
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) {
    return _request(() => _dio.post<dynamic>(path, data: body));
  }

  Future<Map<String, dynamic>> _patch(String path, Map<String, dynamic> body) {
    return _request(() => _dio.patch<dynamic>(path, data: body));
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
}
