import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:ai_model_manager/services/sse_transformer.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiChatService', () {
    test('adds OpenAI reasoning effort and reports cached tokens', () async {
      final adapter = _RecordingAdapter(
        response: _sse([
          {
            'choices': [
              {
                'delta': {'content': 'hello'},
              },
            ],
          },
          {
            'usage': {
              'prompt_tokens': 12,
              'completion_tokens': 5,
              'prompt_tokens_details': {'cached_tokens': 8},
            },
          },
        ]),
      );
      final service = AiChatService(adapterFactory: () => adapter);

      final chunks = await service
          .sendChatChunks(
            provider: _provider(AiProviderType.openai),
            model: 'gpt-test',
            apiKey: 'key',
            messages: [
              {'role': 'user', 'content': 'hi'},
            ],
            systemPrompt: 'system',
            thinkingConfig: const ThinkingConfig(level: ThinkingLevel.high),
          )
          .toList();

      expect(adapter.path, endsWith('/chat/completions'));
      expect(adapter.body['reasoning_effort'], 'high');
      expect(adapter.body['stream_options'], {'include_usage': true});
      expect((chunks.first as TextDelta).text, 'hello');
      final usage = chunks.whereType<UsageReport>().single;
      expect(usage.promptTokens, 12);
      expect(usage.responseTokens, 5);
      expect(usage.cachedTokens, 8);
    });

    test('adds Anthropic cache-control and thinking budget', () async {
      final adapter = _RecordingAdapter(
        response: _sse([
          {
            'type': 'message_start',
            'message': {
              'usage': {
                'input_tokens': 20,
                'output_tokens': 0,
                'cache_read_input_tokens': 11,
              },
            },
          },
        ], event: 'message_start'),
      );
      final service = AiChatService(adapterFactory: () => adapter);

      final chunks = await service
          .sendChatChunks(
            provider: _provider(AiProviderType.anthropic),
            model: 'claude-test',
            apiKey: 'key',
            messages: [
              {'role': 'user', 'content': 'context', 'cache': 'true'},
              {'role': 'assistant', 'content': 'ready', 'cache': 'true'},
              {'role': 'user', 'content': 'question'},
            ],
            systemPrompt: 'system',
            thinkingConfig: const ThinkingConfig(level: ThinkingLevel.low),
          )
          .toList();

      expect(adapter.path, endsWith('/messages'));
      expect(adapter.body['max_tokens'], 16384);
      expect(adapter.body['thinking'], {
        'type': 'enabled',
        'budget_tokens': 1024,
      });

      final system = adapter.body['system'] as List<dynamic>;
      expect(system.single['cache_control'], {'type': 'ephemeral'});

      final messages = adapter.body['messages'] as List<dynamic>;
      expect(messages[0]['content'][0]['cache_control'], {'type': 'ephemeral'});
      expect(messages[1]['content'][0]['cache_control'], {'type': 'ephemeral'});
      expect(messages[2]['content'], 'question');

      final usage = chunks.whereType<UsageReport>().single;
      expect(usage.cachedTokens, 11);
    });
  });

  group('SseTransformer', () {
    test('keeps thinking deltas separate from text deltas', () async {
      final chunks = await SseTransformer.transformChunks(
        Stream.value(
          Uint8List.fromList(
            utf8.encode(
              '${_sseEvent({
                'delta': {'type': 'thinking_delta', 'thinking': 'plan'},
              }, event: 'content_block_delta')}'
              '${_sseEvent({
                'delta': {'type': 'text_delta', 'text': 'answer'},
              }, event: 'content_block_delta')}',
            ),
          ),
        ),
        AiProviderType.anthropic,
      ).toList();

      expect((chunks[0] as ThinkingDelta).text, 'plan');
      expect((chunks[1] as TextDelta).text, 'answer');
    });
  });

  group('AiChatMessage', () {
    test('round-trips token usage fields', () {
      final message = AiChatMessage(
        id: 'm1',
        role: ChatRole.assistant,
        content: 'done',
        createdAt: DateTime.utc(2026),
        promptTokens: 10,
        responseTokens: 3,
        cachedTokens: 7,
      );

      final restored = AiChatMessage.fromJson(message.toJson());

      expect(restored.promptTokens, 10);
      expect(restored.responseTokens, 3);
      expect(restored.cachedTokens, 7);
    });
  });
}

AiProvider _provider(AiProviderType type) {
  return AiProvider(
    id: type.name,
    name: type.label,
    type: type,
    baseUrl: type.defaultBaseUrl,
  );
}

String _sse(List<Map<String, dynamic>> payloads, {String? event}) {
  return payloads.map((payload) => _sseEvent(payload, event: event)).join();
}

String _sseEvent(Map<String, dynamic> payload, {String? event}) {
  final eventLine = event == null ? '' : 'event: $event\n';
  return '${eventLine}data: ${jsonEncode(payload)}\n\n';
}

class _RecordingAdapter implements HttpClientAdapter {
  final String response;
  late Map<String, dynamic> body;
  late String path;

  _RecordingAdapter({required this.response});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    path = options.uri.path;
    body = (options.data as Map).cast<String, dynamic>();
    return ResponseBody.fromString(
      response,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.textPlainContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
