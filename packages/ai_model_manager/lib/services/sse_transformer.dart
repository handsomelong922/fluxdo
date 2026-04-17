import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../models/ai_provider.dart';

/// SSE 数据流解析器
/// 将 Dio ResponseType.stream 的原始字节流转换为文本 token 流
class SseTransformer {
  /// 将字节流转换为 SSE 事件流，提取 delta 文本
  static Stream<String> transform(
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
          final text = _extractDelta(json, providerType, currentEvent);
          if (text != null && text.isNotEmpty) {
            yield text;
          }
        } catch (_) {
          // 解析失败则跳过
        }
      }
    }
  }

  /// 根据供应商类型提取 delta 文本
  static String? _extractDelta(
    Map<String, dynamic> json,
    AiProviderType providerType,
    String? eventType,
  ) {
    switch (providerType) {
      case AiProviderType.openai:
        // OpenAI: choices[0].delta.content
        final choices = json['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) return null;
        final delta = choices[0]['delta'] as Map<String, dynamic>?;
        return delta?['content'] as String?;

      case AiProviderType.openaiResponse:
        // OpenAI Response API: event response.output_text.delta → delta 字段
        if (eventType == 'response.output_text.delta') {
          return json['delta'] as String?;
        }
        return null;

      case AiProviderType.gemini:
        // Gemini: candidates[0].content.parts[0].text
        final candidates = json['candidates'] as List<dynamic>?;
        if (candidates == null || candidates.isEmpty) return null;
        final content = candidates[0]['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List<dynamic>?;
        if (parts == null || parts.isEmpty) return null;
        return parts[0]['text'] as String?;

      case AiProviderType.anthropic:
        // Anthropic: event content_block_delta → delta.text
        if (eventType == 'content_block_delta') {
          final delta = json['delta'] as Map<String, dynamic>?;
          return delta?['text'] as String?;
        }
        return null;
    }
  }
}
