import 'dart:io';

import 'package:dio/dio.dart';
import '../models/ai_provider.dart';

/// AI 供应商 API 服务
class AiProviderApiService {
  /// 从 DioException 中提取用户友好的错误信息
  static String friendlyError(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return '连接超时，请检查网络或 Base URL 是否正确';
        case DioExceptionType.connectionError:
          return '无法连接到服务器，请检查 Base URL 是否正确';
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          final body = error.response?.data;
          // 尝试从响应体中提取错误信息
          String? apiMessage;
          if (body is Map<String, dynamic>) {
            apiMessage = body['error'] is Map
                ? (body['error'] as Map)['message'] as String?
                : body['error'] as String?;
            apiMessage ??= body['message'] as String?;
          }
          if (statusCode == 401) {
            return 'API Key 无效或已过期 (401)';
          } else if (statusCode == 403) {
            return '没有访问权限，请检查 API Key (403)';
          } else if (statusCode == 404) {
            return '接口地址不存在，请检查 Base URL (404)';
          } else if (statusCode == 429) {
            return '请求过于频繁，请稍后重试 (429)';
          } else if (statusCode != null && statusCode >= 500) {
            return '服务器内部错误 ($statusCode)';
          }
          if (apiMessage != null) {
            return apiMessage;
          }
          return '请求失败 ($statusCode)';
        case DioExceptionType.cancel:
          return '请求已取消';
        case DioExceptionType.badCertificate:
          return 'SSL 证书验证失败';
        case DioExceptionType.unknown:
          if (error.error is SocketException) {
            return '网络连接失败，请检查网络设置';
          }
          return '未知网络错误';
      }
    }
    return error.toString();
  }

  /// Anthropic 预定义模型列表
  static const List<AiModel> _anthropicModels = [
    AiModel(id: 'claude-sonnet-4-20250514', name: 'Claude Sonnet 4'),
    AiModel(id: 'claude-opus-4-20250514', name: 'Claude Opus 4'),
    AiModel(id: 'claude-3-5-haiku-20241022', name: 'Claude 3.5 Haiku'),
  ];

  Dio _createDio() {
    return Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));
  }

  /// 拉取模型列表
  Future<List<AiModel>> fetchModels(
    AiProviderType type,
    String baseUrl,
    String apiKey,
  ) async {
    switch (type) {
      case AiProviderType.openai:
      case AiProviderType.openaiResponse:
        return _fetchOpenAiModels(baseUrl, apiKey);
      case AiProviderType.gemini:
        return _fetchGeminiModels(baseUrl, apiKey);
      case AiProviderType.anthropic:
        return _anthropicModels;
    }
  }

  /// 检查连通性
  Future<bool> checkConnectivity(
    AiProviderType type,
    String baseUrl,
    String apiKey,
  ) async {
    try {
      switch (type) {
        case AiProviderType.openai:
        case AiProviderType.openaiResponse:
          return await _checkOpenAiConnectivity(baseUrl, apiKey);
        case AiProviderType.gemini:
          return await _checkGeminiConnectivity(baseUrl, apiKey);
        case AiProviderType.anthropic:
          return await _checkAnthropicConnectivity(baseUrl, apiKey);
      }
    } catch (_) {
      return false;
    }
  }

  Future<List<AiModel>> _fetchOpenAiModels(
      String baseUrl, String apiKey) async {
    final dio = _createDio();
    try {
      final url = '${_trimTrailingSlash(baseUrl)}/models';
      final response = await dio.get(
        url,
        options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      );
      final data = response.data as Map<String, dynamic>;
      final list = data['data'] as List<dynamic>? ?? [];
      final models = list.map((item) {
        final m = item as Map<String, dynamic>;
        return AiModel(id: m['id'] as String);
      }).toList();
      // 按 id 排序
      models.sort((a, b) => a.id.compareTo(b.id));
      return models;
    } finally {
      dio.close();
    }
  }

  Future<List<AiModel>> _fetchGeminiModels(
      String baseUrl, String apiKey) async {
    final dio = _createDio();
    try {
      final url = '${_trimTrailingSlash(baseUrl)}/models';
      final response = await dio.get(
        url,
        queryParameters: {'key': apiKey},
      );
      final data = response.data as Map<String, dynamic>;
      final list = data['models'] as List<dynamic>? ?? [];
      final models = list.map((item) {
        final m = item as Map<String, dynamic>;
        final name = m['name'] as String? ?? '';
        // Gemini 返回 models/gemini-xxx，取后半段作为 id
        final id = name.startsWith('models/') ? name.substring(7) : name;
        final displayName = m['displayName'] as String?;
        return AiModel(id: id, name: displayName);
      }).toList();
      models.sort((a, b) => a.id.compareTo(b.id));
      return models;
    } finally {
      dio.close();
    }
  }

  Future<bool> _checkOpenAiConnectivity(
      String baseUrl, String apiKey) async {
    final dio = _createDio();
    try {
      final url = '${_trimTrailingSlash(baseUrl)}/models';
      final response = await dio.get(
        url,
        options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      );
      return response.statusCode == 200;
    } finally {
      dio.close();
    }
  }

  Future<bool> _checkGeminiConnectivity(
      String baseUrl, String apiKey) async {
    final dio = _createDio();
    try {
      final url = '${_trimTrailingSlash(baseUrl)}/models';
      final response = await dio.get(
        url,
        queryParameters: {'key': apiKey},
      );
      return response.statusCode == 200;
    } finally {
      dio.close();
    }
  }

  Future<bool> _checkAnthropicConnectivity(
      String baseUrl, String apiKey) async {
    final dio = _createDio();
    try {
      final url = '${_trimTrailingSlash(baseUrl)}/messages';
      final response = await dio.post(
        url,
        data: {
          'model': 'claude-sonnet-4-20250514',
          'max_tokens': 1,
          'messages': [
            {'role': 'user', 'content': 'hi'}
          ],
        },
        options: Options(headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        }),
      );
      // 200 或 400（参数错误但说明连通）都算成功
      return response.statusCode == 200;
    } on DioException catch (e) {
      // 400 说明 API Key 有效，只是请求参数不满足
      if (e.response?.statusCode == 400) return true;
      return false;
    } finally {
      dio.close();
    }
  }

  /// 测试指定模型是否可用（发送最小请求）
  ///
  /// 成功返回 null，失败返回错误信息
  Future<String?> testModel(
    AiProviderType type,
    String baseUrl,
    String apiKey,
    String modelId,
  ) async {
    final dio = _createDio();
    final url = _trimTrailingSlash(baseUrl);
    try {
      switch (type) {
        case AiProviderType.openai:
          await dio.post(
            '$url/chat/completions',
            data: {
              'model': modelId,
              'messages': [
                {'role': 'user', 'content': 'hi'}
              ],
              'max_tokens': 1,
            },
            options: Options(headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            }),
          );

        case AiProviderType.openaiResponse:
          await dio.post(
            '$url/responses',
            data: {
              'model': modelId,
              'input': 'hi',
              'max_output_tokens': 1,
            },
            options: Options(headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            }),
          );

        case AiProviderType.gemini:
          await dio.post(
            '$url/models/$modelId:generateContent',
            queryParameters: {'key': apiKey},
            data: {
              'contents': [
                {
                  'parts': [
                    {'text': 'hi'}
                  ]
                }
              ],
              'generationConfig': {'maxOutputTokens': 1},
            },
            options: Options(headers: {
              'Content-Type': 'application/json',
            }),
          );

        case AiProviderType.anthropic:
          await dio.post(
            '$url/messages',
            data: {
              'model': modelId,
              'max_tokens': 1,
              'messages': [
                {'role': 'user', 'content': 'hi'}
              ],
            },
            options: Options(headers: {
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
              'Content-Type': 'application/json',
            }),
          );
      }
      return null; // 成功
    } catch (e) {
      return friendlyError(e);
    } finally {
      dio.close();
    }
  }

  String _trimTrailingSlash(String url) {
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }
}
