import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/ai_provider.dart';
import 'sse_transformer.dart';

/// AI 聊天服务，支持流式响应
class AiChatService {
  final HttpClientAdapter Function()? _adapterFactory;

  AiChatService({HttpClientAdapter Function()? adapterFactory})
      : _adapterFactory = adapterFactory;

  Dio _createDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 5),
    ));
    if (_adapterFactory != null) {
      dio.httpClientAdapter = _adapterFactory!();
    }
    return dio;
  }

  /// 发送聊天消息并返回流式响应
  Stream<String> sendChatStream({
    required AiProvider provider,
    required String model,
    required String apiKey,
    required List<Map<String, String>> messages,
    String? systemPrompt,
  }) async* {
    final dio = _createDio();
    try {
      final baseUrl = _trimTrailingSlash(provider.baseUrl);

      late final Response<ResponseBody> response;

      switch (provider.type) {
        case AiProviderType.openai:
          response = await _sendOpenAi(
            dio, baseUrl, apiKey, model, messages, systemPrompt,
          );

        case AiProviderType.openaiResponse:
          response = await _sendOpenAiResponse(
            dio, baseUrl, apiKey, model, messages, systemPrompt,
          );

        case AiProviderType.gemini:
          response = await _sendGemini(
            dio, baseUrl, apiKey, model, messages, systemPrompt,
          );

        case AiProviderType.anthropic:
          response = await _sendAnthropic(
            dio, baseUrl, apiKey, model, messages, systemPrompt,
          );
      }

      final byteStream = response.data!.stream.cast<Uint8List>();
      yield* SseTransformer.transform(byteStream, provider.type);
    } finally {
      dio.close();
    }
  }

  Future<Response<ResponseBody>> _sendOpenAi(
    Dio dio,
    String baseUrl,
    String apiKey,
    String model,
    List<Map<String, String>> messages,
    String? systemPrompt,
  ) {
    final allMessages = <Map<String, String>>[
      if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
      ...messages,
    ];

    return dio.post<ResponseBody>(
      '$baseUrl/chat/completions',
      data: {
        'model': model,
        'messages': allMessages,
        'stream': true,
      },
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.stream,
      ),
    );
  }

  Future<Response<ResponseBody>> _sendOpenAiResponse(
    Dio dio,
    String baseUrl,
    String apiKey,
    String model,
    List<Map<String, String>> messages,
    String? systemPrompt,
  ) {
    // OpenAI Response API 使用 input 数组
    final input = <Map<String, String>>[
      if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
      ...messages,
    ];

    return dio.post<ResponseBody>(
      '$baseUrl/responses',
      data: {
        'model': model,
        'input': input,
        'stream': true,
      },
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.stream,
      ),
    );
  }

  Future<Response<ResponseBody>> _sendGemini(
    Dio dio,
    String baseUrl,
    String apiKey,
    String model,
    List<Map<String, String>> messages,
    String? systemPrompt,
  ) {
    // Gemini 使用 contents 格式
    final contents = messages.map((m) {
      final role = m['role'] == 'assistant' ? 'model' : 'user';
      return {
        'role': role,
        'parts': [
          {'text': m['content']},
        ],
      };
    }).toList();

    final data = <String, dynamic>{
      'contents': contents,
    };

    if (systemPrompt != null) {
      data['systemInstruction'] = {
        'parts': [
          {'text': systemPrompt},
        ],
      };
    }

    return dio.post<ResponseBody>(
      '$baseUrl/models/$model:streamGenerateContent',
      queryParameters: {
        'key': apiKey,
        'alt': 'sse',
      },
      data: data,
      options: Options(
        headers: {'Content-Type': 'application/json'},
        responseType: ResponseType.stream,
      ),
    );
  }

  Future<Response<ResponseBody>> _sendAnthropic(
    Dio dio,
    String baseUrl,
    String apiKey,
    String model,
    List<Map<String, String>> messages,
    String? systemPrompt,
  ) {
    final data = <String, dynamic>{
      'model': model,
      'messages': messages,
      'max_tokens': 8192,
      'stream': true,
    };

    if (systemPrompt != null) {
      data['system'] = systemPrompt;
    }

    return dio.post<ResponseBody>(
      '$baseUrl/messages',
      data: data,
      options: Options(
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.stream,
      ),
    );
  }

  String _trimTrailingSlash(String url) {
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }
}
