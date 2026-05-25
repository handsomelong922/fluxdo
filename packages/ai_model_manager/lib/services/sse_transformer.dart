import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../models/ai_chat_chunk.dart';
import '../models/ai_provider.dart';

/// SSE 数据流解析器
/// 将 Dio ResponseType.stream 的原始字节流转换为文本 token 流
class SseTransformer {
  /// 将字节流转换为 SSE 事件流，提取 delta 文本
  static Stream<String> transform(
    Stream<Uint8List> byteStream,
    AiProviderType providerType,
  ) async* {
    await for (final chunk in transformChunks(byteStream, providerType)) {
      if (chunk is TextDelta && chunk.text.isNotEmpty) {
        yield chunk.text;
      }
    }
  }

  /// 将字节流转换为结构化 SSE 事件流。
  static Stream<AiChatChunk> transformChunks(
    Stream<Uint8List> byteStream,
    AiProviderType providerType,
  ) async* {
    final buffer = StringBuffer();

    await for (final chunk in byteStream) {
      buffer.write(utf8.decode(chunk, allowMalformed: true));

      // 按行分割处理
      var content = buffer.toString();
      final lines = content.split('\n');

      // 最后一行可能不完整，保留在 buffer 中
      buffer.clear();
      if (!content.endsWith('\n')) {
        buffer.write(lines.removeLast());
      } else {
        // 移除最后的空行
        if (lines.isNotEmpty && lines.last.isEmpty) {
          lines.removeLast();
        }
      }

      String? currentEvent;
      for (final line in lines) {
        if (line.startsWith('event:')) {
          currentEvent = line.substring(6).trim();
          continue;
        }

        if (!line.startsWith('data:')) {
          if (line.isEmpty) currentEvent = null;
          continue;
        }

        final data = line.substring(5).trim();
        if (data == '[DONE]') continue;
        if (data.isEmpty) continue;

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final extracted = _extractChunk(json, providerType, currentEvent);
          if (extracted != null) {
            yield extracted;
          }
        } catch (_) {
          // 解析失败则跳过
        }
      }
    }
  }

  /// 根据供应商类型提取结构化响应片段。
  static AiChatChunk? _extractChunk(
    Map<String, dynamic> json,
    AiProviderType providerType,
    String? eventType,
  ) {
    final usage = _extractUsage(json, providerType, eventType);
    if (usage != null) return usage;

    switch (providerType) {
      case AiProviderType.openai:
        // OpenAI: choices[0].delta.content
        final choices = json['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) return null;
        final delta = choices[0]['delta'] as Map<String, dynamic>?;
        final text = delta?['content'] as String?;
        return text == null || text.isEmpty ? null : TextDelta(text);

      case AiProviderType.openaiResponse:
        // OpenAI Response API: event response.output_text.delta → delta 字段
        if (eventType == 'response.output_text.delta') {
          final text = json['delta'] as String?;
          return text == null || text.isEmpty ? null : TextDelta(text);
        }
        return null;

      case AiProviderType.gemini:
        // Gemini: candidates[0].content.parts[0].text
        final candidates = json['candidates'] as List<dynamic>?;
        if (candidates == null || candidates.isEmpty) return null;
        final content = candidates[0]['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List<dynamic>?;
        if (parts == null || parts.isEmpty) return null;
        final firstPart = parts[0] as Map<String, dynamic>?;
        final text = firstPart?['text'] as String?;
        if (text == null || text.isEmpty) return null;
        return firstPart?['thought'] == true
            ? ThinkingDelta(text)
            : TextDelta(text);

      case AiProviderType.anthropic:
        // Anthropic: event content_block_delta → delta.text / delta.thinking
        if (eventType == 'content_block_delta') {
          final delta = json['delta'] as Map<String, dynamic>?;
          final type = delta?['type'] as String?;
          final thinking = delta?['thinking'] as String?;
          if (thinking != null && thinking.isNotEmpty) {
            return ThinkingDelta(thinking);
          }
          final text = delta?['text'] as String?;
          if (text == null || text.isEmpty) return null;
          return type == 'thinking_delta'
              ? ThinkingDelta(text)
              : TextDelta(text);
        }
        return null;
    }
  }

  static UsageReport? _extractUsage(
    Map<String, dynamic> json,
    AiProviderType providerType,
    String? eventType,
  ) {
    switch (providerType) {
      case AiProviderType.openai:
        return _openAiUsage(json['usage'] as Map<String, dynamic>?);
      case AiProviderType.openaiResponse:
        if (eventType != null && !eventType.contains('completed')) {
          return null;
        }
        final response = json['response'] as Map<String, dynamic>?;
        return _openAiResponseUsage(
          (response?['usage'] ?? json['usage']) as Map<String, dynamic>?,
        );
      case AiProviderType.gemini:
        final usage = json['usageMetadata'] as Map<String, dynamic>?;
        if (usage == null) return null;
        return UsageReport(
          promptTokens: usage['promptTokenCount'] as int?,
          responseTokens: usage['candidatesTokenCount'] as int?,
          cachedTokens: usage['cachedContentTokenCount'] as int?,
        );
      case AiProviderType.anthropic:
        final message = json['message'] as Map<String, dynamic>?;
        final usage =
            (message?['usage'] ?? json['usage']) as Map<String, dynamic>?;
        if (usage == null) return null;
        return UsageReport(
          promptTokens: usage['input_tokens'] as int?,
          responseTokens: usage['output_tokens'] as int?,
          cachedTokens: usage['cache_read_input_tokens'] as int?,
        );
    }
  }

  static UsageReport? _openAiUsage(Map<String, dynamic>? usage) {
    if (usage == null) return null;
    final details = usage['prompt_tokens_details'] as Map<String, dynamic>?;
    return UsageReport(
      promptTokens: usage['prompt_tokens'] as int?,
      responseTokens: usage['completion_tokens'] as int?,
      cachedTokens: details?['cached_tokens'] as int?,
    );
  }

  static UsageReport? _openAiResponseUsage(Map<String, dynamic>? usage) {
    if (usage == null) return null;
    final details = usage['input_tokens_details'] as Map<String, dynamic>?;
    return UsageReport(
      promptTokens: usage['input_tokens'] as int?,
      responseTokens: usage['output_tokens'] as int?,
      cachedTokens: details?['cached_tokens'] as int?,
    );
  }
}
