/// AI 聊天流式响应片段。
sealed class AiChatChunk {
  const AiChatChunk();
}

/// 普通文本增量。
class TextDelta extends AiChatChunk {
  final String text;

  const TextDelta(this.text);
}

/// 模型思考过程增量。
///
/// 当前 UI 不展示思考内容，只保留类型，避免把 reasoning 内容混入最终回复。
class ThinkingDelta extends AiChatChunk {
  final String text;

  const ThinkingDelta(this.text);
}

/// Token 用量报告，通常在流结束附近返回。
class UsageReport extends AiChatChunk {
  final int? promptTokens;
  final int? responseTokens;
  final int? cachedTokens;

  const UsageReport({
    this.promptTokens,
    this.responseTokens,
    this.cachedTokens,
  });
}
