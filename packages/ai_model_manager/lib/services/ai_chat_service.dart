import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as a;
import 'package:dio/dio.dart' show DioException, DioExceptionType;
import 'package:googleai_dart/googleai_dart.dart' as g;
import 'package:http/http.dart' as http;
import 'package:openai_dart/openai_dart.dart' as o;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../l10n/ai_l10n.dart';
import '../models/ai_chat_attachment.dart';
import '../models/ai_chat_message.dart';
import '../models/ai_provider.dart';

/// 流式响应中的事件类型（统一各 SDK 输出）
sealed class AiChatChunk {
  const AiChatChunk();
}

/// 正文文本增量
class TextDelta extends AiChatChunk {
  const TextDelta(this.text);
  final String text;
}

/// 思考块（reasoning）文本增量
/// - Anthropic: Extended Thinking 块
/// - OpenAI: reasoning_content / reasoning（DeepSeek R1 / OpenRouter / vLLM 等）
class ThinkingDelta extends AiChatChunk {
  const ThinkingDelta(this.text);
  final String text;
}

/// Token 用量报告，流结束时发送
class UsageReport extends AiChatChunk {
  const UsageReport({this.promptTokens, this.responseTokens});
  final int? promptTokens;
  final int? responseTokens;
}

/// 模型生成的图片（gpt-image / DALL-E 等）
///
/// 字节已写到本地文件，调用方持久化 [localPath] 即可。
///
/// 渐进式生成（partial_images）会先发送若干 [partialImageIndex] != null 的中间帧
/// （草图），最后才发送 [partialImageIndex] == null 的终态图。
/// 上层在收到终态图时应清掉所有 partial 帧。
class ImageGenerated extends AiChatChunk {
  const ImageGenerated({
    required this.localPath,
    required this.mimeType,
    this.partialImageIndex,
  });
  final String localPath;
  final String mimeType;
  final int? partialImageIndex;

  bool get isPartial => partialImageIndex != null;
}

/// AI 聊天服务：直接基于各 LLM provider 的 SDK 实现统一流式接口。
///
/// - OpenAI / OpenAI Responses → `openai_dart` 4.x
/// - Anthropic（含 Extended Thinking）→ `anthropic_sdk_dart`
/// - Gemini → `googleai_dart`
///
/// 所有 SDK 都基于 `package:http`，通过 [bridgedClient] 注入应用 dio 网络栈。
class AiChatService {
  AiChatService({this.bridgedClient});

  /// 可选 http.Client。传 [DioBackedHttpClient] 即可让所有请求复用应用网络栈。
  final http.Client? bridgedClient;

  Stream<AiChatChunk> sendChatStream({
    required AiProvider provider,
    required String model,
    required String apiKey,
    required List<AiChatMessage> messages,
    String? systemPrompt,
    bool enableThinking = false,
    int thinkingBudgetTokens = 4096,
  }) {
    // OpenAI 系图像模型（gpt-image-* / dall-e-*）走 /images/generations 端点，
    // 不能套聊天接口。模仿 Kelivo 的路由策略：从最后一条 user 消息抽 prompt，
    // 有附件则走 /images/edits，否则 /images/generations。
    if (_isOpenAIImageRoute(provider, model)) {
      return _streamOpenAiImageGeneration(
        baseUrl: provider.baseUrl,
        apiKey: apiKey,
        model: model,
        messages: messages,
      );
    }
    switch (provider.type) {
      case AiProviderType.openai:
        return _streamOpenAi(
          baseUrl: provider.baseUrl,
          apiKey: apiKey,
          model: model,
          messages: messages,
          systemPrompt: systemPrompt,
        );
      case AiProviderType.openaiResponse:
        return _streamOpenAiResponses(
          baseUrl: provider.baseUrl,
          apiKey: apiKey,
          model: model,
          messages: messages,
          systemPrompt: systemPrompt,
        );
      case AiProviderType.gemini:
        return _streamGemini(
          baseUrl: provider.baseUrl,
          apiKey: apiKey,
          model: model,
          messages: messages,
          systemPrompt: systemPrompt,
        );
      case AiProviderType.anthropic:
        return _streamAnthropic(
          baseUrl: provider.baseUrl,
          apiKey: apiKey,
          model: model,
          messages: messages,
          systemPrompt: systemPrompt,
          enableThinking: enableThinking,
          thinkingBudgetTokens: thinkingBudgetTokens,
        );
    }
  }

  /// 检测是否为 OpenAI 系图像生成模型（gpt-image-* / chatgpt-image-* / dall-e-*）。
  /// 仅 openai / openaiResponse provider 类型适用。
  bool _isOpenAIImageRoute(AiProvider provider, String modelId) {
    if (provider.type != AiProviderType.openai &&
        provider.type != AiProviderType.openaiResponse) {
      return false;
    }
    final id = modelId.toLowerCase();
    return id.startsWith('gpt-image-') ||
        id.startsWith('chatgpt-image-') ||
        id == 'dall-e-2' ||
        id == 'dall-e-3';
  }

  // ────────────────────────── OpenAI Chat Completions ──────────────────────────

  Stream<AiChatChunk> _streamOpenAi({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiChatMessage> messages,
    String? systemPrompt,
  }) async* {
    final client = _createOpenAIClient(baseUrl, apiKey);
    try {
      final request = o.ChatCompletionCreateRequest(
        model: model,
        messages: _toOpenAiMessages(systemPrompt, messages),
        streamOptions: const o.StreamOptions(includeUsage: true),
      );
      int? promptTokens;
      int? responseTokens;
      try {
        await for (final event in client.chat.completions.createStream(
          request,
        )) {
          final delta = event.choices?.firstOrNull?.delta;
          if (delta != null) {
            final text = delta.content;
            if (text != null && text.isNotEmpty) yield TextDelta(text);
            final reasoning = delta.reasoningContent ?? delta.reasoning;
            if (reasoning != null && reasoning.isNotEmpty) {
              yield ThinkingDelta(reasoning);
            }
          }
          final usage = event.usage;
          if (usage != null) {
            promptTokens = usage.promptTokens;
            responseTokens = usage.completionTokens;
          }
        }
      } catch (e) {
        throw _mapError(e);
      }
      if (promptTokens != null || responseTokens != null) {
        yield UsageReport(
          promptTokens: promptTokens,
          responseTokens: responseTokens,
        );
      }
    } finally {
      client.close();
    }
  }

  /// 对 5xx 错误自动重试（含 502/503/504 上游代理超时）。
  ///
  /// openai_dart 4.x 默认只对幂等方法（GET/PUT/DELETE 等）重试 5xx，
  /// POST 不重试。而代理服务器（one-api / aihubmix）的 504 通常不是
  /// OpenAI 真的故障，重试一下大概率能成功。Cherry Studio 用的 Vercel AI SDK
  /// 默认对 POST 也重试 5xx，体验更好。
  Future<T> _withServerErrorRetry<T>(
    Future<T> Function() task, {
    int maxAttempts = 3,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await task();
      } catch (e) {
        lastError = e;
        final shouldRetry = _isTransientServerError(e) && attempt < maxAttempts;
        if (!shouldRetry) rethrow;
        // 指数退避：2s, 4s, 8s（最多 8s）
        final waitSec = 1 << attempt;
        await Future<void>.delayed(Duration(seconds: waitSec.clamp(2, 8)));
      }
    }
    throw lastError!;
  }

  bool _isTransientServerError(Object e) {
    if (e is o.InternalServerException) {
      // 502 / 503 / 504 是典型的上游瞬时问题，500 可能是 OpenAI 真的故障也重试
      return e.statusCode >= 500 && e.statusCode < 600;
    }
    return false;
  }

  // ────────────────────────── OpenAI Images API（gpt-image / DALL-E） ──────────────────────────

  Stream<AiChatChunk> _streamOpenAiImageGeneration({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiChatMessage> messages,
  }) async* {
    // 提取最后一条 user 消息作为 prompt
    AiChatMessage? lastUser;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == ChatRole.user) {
        lastUser = messages[i];
        break;
      }
    }
    final prompt = (lastUser?.content ?? '').trim();
    if (prompt.isEmpty) {
      throw Exception(AiL10n.current.emptyResponseError);
    }

    final inputAttachments = lastUser?.attachments ?? const [];
    final hasInput = inputAttachments.isNotEmpty;

    final client = _createOpenAIClient(baseUrl, apiKey);
    try {
      // gpt-image 系列原生支持流式 partial frames（先发草图后发终态）。
      // dall-e-2/3 不支持 stream，会被 SDK 自动忽略 stream 参数走非流式。
      // 用 partialImages: 2 让用户更早看到雏形（5-10s 出第一张草图，30s 出终态）。
      final supportsPartial = _supportsPartialImages(model);
      final partialImages = supportsPartial ? 2 : null;

      try {
        if (hasInput) {
          final att = inputAttachments.first;
          final bytes = await _attachmentBytes(att);
          if (supportsPartial) {
            yield* _consumeImageEditStream(
              client.images.editStream(
                o.ImageEditRequest(
                  model: model,
                  prompt: prompt,
                  image: bytes,
                  imageFilename: 'input.${_extFromMime(att.mimeType)}',
                  partialImages: partialImages,
                ),
              ),
            );
          } else {
            // 504/502/503 自动重试 3 次（绕过 openai_dart 4.x 对 POST 不重试的限制）
            final response = await _withServerErrorRetry(() => client.images.edit(
              o.ImageEditRequest(
                model: model,
                prompt: prompt,
                image: bytes,
                imageFilename: 'input.${_extFromMime(att.mimeType)}',
              ),
            ));
            yield* _emitImageResponse(response);
          }
        } else {
          if (supportsPartial) {
            yield* _consumeImageGenStream(
              client.images.generateStream(
                o.ImageGenerationRequest(
                  model: model,
                  prompt: prompt,
                  partialImages: partialImages,
                ),
              ),
            );
          } else {
            final response = await _withServerErrorRetry(() => client.images.generate(
              o.ImageGenerationRequest(model: model, prompt: prompt),
            ));
            yield* _emitImageResponse(response);
          }
        }
      } catch (e) {
        throw _mapError(e);
      }
    } finally {
      client.close();
    }
  }

  /// 是否启用 streaming + partial_images。
  ///
  /// 当前默认 **关闭**，原因：
  /// - OpenAI gpt-image streaming 要求 organization 完成 verification，
  ///   未验证的 org 会收到 200 响应但 stream 立即关闭、无任何事件，
  ///   表现为「未收到 AI 回复」错误（onDone 时 buffer 空）。
  /// - 部分 OpenAI 兼容服务器对 `partial_images` 参数不熟。
  /// - 非流式 `generate()` 走 `_emitImageResponse` 路径稳定可靠。
  ///
  /// 待后续验证 org 普及后再考虑默认开启，或加用户开关。
  bool _supportsPartialImages(String modelId) {
    return false;
  }

  /// 消费 generateStream 事件流，把 partial 帧和终态帧统一映射成 [ImageGenerated]
  Stream<AiChatChunk> _consumeImageGenStream(
    Stream<o.ImageGenStreamEvent> stream,
  ) async* {
    await for (final event in stream) {
      switch (event) {
        case o.ImageGenPartialImageEvent e:
          final mime = _outputFormatToMime(e.outputFormat);
          final localPath = await _decodeAndSave(e.b64Json, mime);
          yield ImageGenerated(
            localPath: localPath,
            mimeType: mime,
            partialImageIndex: e.partialImageIndex,
          );
        case o.ImageGenCompletedEvent e:
          final mime = _outputFormatToMime(e.outputFormat);
          final localPath = await _decodeAndSave(e.b64Json, mime);
          yield ImageGenerated(localPath: localPath, mimeType: mime);
          yield UsageReport(
            promptTokens: e.usage.inputTokens,
            responseTokens: e.usage.outputTokens,
          );
        case o.ImageGenUnknownEvent _:
          break;
      }
    }
  }

  /// 消费 editStream 事件流，同 [_consumeImageGenStream] 风格
  Stream<AiChatChunk> _consumeImageEditStream(
    Stream<o.ImageEditStreamEvent> stream,
  ) async* {
    await for (final event in stream) {
      switch (event) {
        case o.ImageEditPartialImageEvent e:
          final mime = _outputFormatToMime(e.outputFormat);
          final localPath = await _decodeAndSave(e.b64Json, mime);
          yield ImageGenerated(
            localPath: localPath,
            mimeType: mime,
            partialImageIndex: e.partialImageIndex,
          );
        case o.ImageEditCompletedEvent e:
          final mime = _outputFormatToMime(e.outputFormat);
          final localPath = await _decodeAndSave(e.b64Json, mime);
          yield ImageGenerated(localPath: localPath, mimeType: mime);
          yield UsageReport(
            promptTokens: e.usage.inputTokens,
            responseTokens: e.usage.outputTokens,
          );
        case o.ImageEditUnknownEvent _:
          break;
      }
    }
  }

  String _outputFormatToMime(o.ImageOutputFormat fmt) {
    switch (fmt.toJson()) {
      case 'jpeg':
      case 'jpg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'png':
      default:
        return 'image/png';
    }
  }

  Future<String> _decodeAndSave(String b64, String mime) async {
    final cleaned = b64.replaceAll(RegExp(r'\s'), '');
    final Uint8List bytes;
    try {
      bytes = base64Decode(cleaned);
    } catch (e) {
      throw Exception('Failed to decode image base64: $e');
    }
    return _saveImageBytes(bytes, mime);
  }

  /// 非流式响应回退：dall-e 系列走这里
  Stream<AiChatChunk> _emitImageResponse(o.ImageResponse response) async* {
    final outputMime = _imageResponseMime(response);
    for (final image in response.data) {
      final url = image.url;
      if (url != null && url.isNotEmpty) {
        final bytes = await _downloadImage(url);
        final localPath = await _saveImageBytes(bytes, outputMime);
        yield ImageGenerated(localPath: localPath, mimeType: outputMime);
        continue;
      }
      final b64 = image.b64Json;
      if (b64 == null || b64.isEmpty) continue;
      final localPath = await _decodeAndSave(b64, outputMime);
      yield ImageGenerated(localPath: localPath, mimeType: outputMime);
    }
    final usage = response.usage;
    if (usage != null) {
      yield UsageReport(
        promptTokens: usage.inputTokens,
        responseTokens: usage.outputTokens,
      );
    }
  }

  Future<Uint8List> _attachmentBytes(AiChatAttachment att) async {
    final base64Data = att.base64Data;
    if (base64Data != null && base64Data.isNotEmpty) {
      return base64Decode(base64Data.replaceAll(RegExp(r'\s'), ''));
    }
    final localPath = att.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      return File(localPath).readAsBytes();
    }
    final remoteUrl = att.remoteUrl;
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      return _downloadImage(remoteUrl);
    }
    throw Exception('Attachment has no usable image source');
  }

  Future<Uint8List> _downloadImage(String url) async {
    final client = bridgedClient ?? http.Client();
    try {
      final resp = await client.get(Uri.parse(url));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('Failed to download image: HTTP ${resp.statusCode}');
      }
      return resp.bodyBytes;
    } finally {
      // 仅当 fallback http.Client() 时关闭；bridgedClient 由外部管理
      if (bridgedClient == null) client.close();
    }
  }

  Future<String> _saveImageBytes(Uint8List bytes, String mime) async {
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(dir.path, 'ai_generated_images'));
    if (!imagesDir.existsSync()) imagesDir.createSync(recursive: true);
    final ext = _extFromMime(mime);
    final filename = '${DateTime.now().millisecondsSinceEpoch}_'
        '${const Uuid().v4().substring(0, 8)}.$ext';
    final file = File(p.join(imagesDir.path, filename));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  String _imageResponseMime(o.ImageResponse response) {
    final fmt = response.outputFormat?.toJson();
    switch (fmt) {
      case 'jpeg':
      case 'jpg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'png':
        return 'image/png';
    }
    // gpt-image 系列默认 png
    return 'image/png';
  }

  String _extFromMime(String mime) {
    switch (mime.toLowerCase()) {
      case 'image/jpeg':
      case 'image/jpg':
        return 'jpg';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      case 'image/png':
      default:
        return 'png';
    }
  }

  // ────────────────────────── OpenAI Responses API ──────────────────────────

  Stream<AiChatChunk> _streamOpenAiResponses({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiChatMessage> messages,
    String? systemPrompt,
  }) async* {
    final client = _createOpenAIClient(baseUrl, apiKey);
    try {
      final request = o.CreateResponseRequest(
        model: model,
        input: _toResponsesInput(messages),
        instructions: systemPrompt,
      );
      int? promptTokens;
      int? responseTokens;
      try {
        await for (final event in client.responses.createStream(request)) {
          switch (event) {
            case final o.OutputTextDeltaEvent e:
              if (e.delta.isNotEmpty) yield TextDelta(e.delta);
            case final o.ResponseCompletedEvent e:
              promptTokens = e.response.usage?.inputTokens;
              responseTokens = e.response.usage?.outputTokens;
            case final o.ResponseFailedEvent e:
              throw Exception(
                e.response.error?.message ?? 'Responses API failed',
              );
            default:
              break;
          }
        }
      } catch (e) {
        throw _mapError(e);
      }
      if (promptTokens != null || responseTokens != null) {
        yield UsageReport(
          promptTokens: promptTokens,
          responseTokens: responseTokens,
        );
      }
    } finally {
      client.close();
    }
  }

  o.OpenAIClient _createOpenAIClient(String baseUrl, String apiKey) {
    return o.OpenAIClient(
      config: o.OpenAIConfig(
        authProvider: o.ApiKeyProvider(apiKey),
        baseUrl: _trimTrailingSlash(baseUrl),
      ),
      httpClient: bridgedClient,
    );
  }

  // ────────────────────────── Gemini ──────────────────────────

  Stream<AiChatChunk> _streamGemini({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiChatMessage> messages,
    String? systemPrompt,
  }) async* {
    final client = g.GoogleAIClient(
      config: g.GoogleAIConfig(
        authProvider: g.ApiKeyProvider(apiKey),
        baseUrl: baseUrl.isEmpty
            ? 'https://generativelanguage.googleapis.com'
            : _stripGeminiVersion(baseUrl),
        apiMode: g.ApiMode.googleAI,
      ),
      httpClient: bridgedClient,
    );
    try {
      final request = g.GenerateContentRequest(
        contents: _toGeminiContents(messages),
        systemInstruction: systemPrompt == null
            ? null
            : g.Content(parts: [g.Part.text(systemPrompt)]),
      );
      int? promptTokens;
      int? responseTokens;
      try {
        await for (final response in client.models.streamGenerateContent(
          model: model,
          request: request,
        )) {
          final parts = response.candidates?.firstOrNull?.content?.parts ?? [];
          for (final part in parts) {
            if (part is g.TextPart && part.text.isNotEmpty) {
              yield TextDelta(part.text);
            }
          }
          final usage = response.usageMetadata;
          if (usage != null) {
            promptTokens = usage.promptTokenCount;
            responseTokens = usage.candidatesTokenCount;
          }
        }
      } catch (e) {
        throw _mapError(e);
      }
      if (promptTokens != null || responseTokens != null) {
        yield UsageReport(
          promptTokens: promptTokens,
          responseTokens: responseTokens,
        );
      }
    } finally {
      client.close();
    }
  }

  // ────────────────────────── Anthropic（含 Extended Thinking） ──────────────────────────

  Stream<AiChatChunk> _streamAnthropic({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiChatMessage> messages,
    String? systemPrompt,
    bool enableThinking = false,
    int thinkingBudgetTokens = 4096,
  }) async* {
    final client = a.AnthropicClient(
      apiKey: apiKey,
      baseUrl: baseUrl.isEmpty ? null : _trimTrailingSlash(baseUrl),
      client: bridgedClient,
    );

    final request = a.CreateMessageRequest(
      model: a.Model.modelId(model),
      messages: _toAnthropicMessages(messages),
      maxTokens: 8192,
      system: systemPrompt == null
          ? null
          : a.CreateMessageRequestSystem.text(systemPrompt),
      thinking: enableThinking
          ? a.ThinkingConfig.enabled(
              type: a.ThinkingConfigEnabledType.enabled,
              budgetTokens: thinkingBudgetTokens,
            )
          : null,
    );

    int? promptTokens;
    int? responseTokens;
    try {
      await for (final event in client.createMessageStream(request: request)) {
        switch (event) {
          case final a.MessageStartEvent e:
            promptTokens = e.message.usage?.inputTokens;
            responseTokens = e.message.usage?.outputTokens;
          case final a.ContentBlockDeltaEvent e:
            switch (e.delta) {
              case final a.TextBlockDelta d:
                if (d.text.isNotEmpty) yield TextDelta(d.text);
              case final a.ThinkingBlockDelta d:
                if (d.thinking.isNotEmpty) yield ThinkingDelta(d.thinking);
              default:
                break;
            }
          case final a.MessageDeltaEvent e:
            // MessageDelta 阶段的 usage 是 output 的最终值
            responseTokens = e.usage.outputTokens;
          default:
            break;
        }
      }
    } catch (e) {
      throw _mapError(e);
    } finally {
      client.endSession();
    }

    if (promptTokens != null || responseTokens != null) {
      yield UsageReport(
        promptTokens: promptTokens,
        responseTokens: responseTokens,
      );
    }
  }

  // ────────────────────────── 消息转换：OpenAI Chat Completions ──────────────────────────

  List<o.ChatMessage> _toOpenAiMessages(
    String? systemPrompt,
    List<AiChatMessage> history,
  ) {
    final result = <o.ChatMessage>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      result.add(o.ChatMessage.system(systemPrompt));
    }
    for (final msg in history) {
      switch (msg.role) {
        case ChatRole.system:
          result.add(o.ChatMessage.system(msg.content));
        case ChatRole.user:
          final attachments = msg.attachments;
          if (attachments == null || attachments.isEmpty) {
            result.add(o.ChatMessage.user(msg.content));
          } else {
            final parts = <o.ContentPart>[
              if (msg.content.isNotEmpty) o.ContentPart.text(msg.content),
              for (final att in attachments)
                if (_openAiImagePart(att) case final p?) p,
            ];
            result.add(o.ChatMessage.user(parts));
          }
        case ChatRole.assistant:
          if (msg.content.isEmpty) continue;
          result.add(o.ChatMessage.assistant(content: msg.content));
      }
    }
    return result;
  }

  o.ContentPart? _openAiImagePart(AiChatAttachment att) {
    final remote = att.remoteUrl;
    if (remote != null && remote.isNotEmpty) {
      return o.ContentPart.imageUrl(remote);
    }
    final base64Data = att.base64Data;
    if (base64Data != null && base64Data.isNotEmpty) {
      return o.ContentPart.imageBase64(
        data: base64Data,
        mediaType: att.mimeType,
      );
    }
    final localPath = att.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      final bytes = File(localPath).readAsBytesSync();
      return o.ContentPart.imageBase64(
        data: base64Encode(bytes),
        mediaType: att.mimeType,
      );
    }
    return null;
  }

  // ────────────────────────── 消息转换：OpenAI Responses ──────────────────────────

  o.ResponseInput _toResponsesInput(List<AiChatMessage> history) {
    if (history.length == 1 && history.first.role == ChatRole.user) {
      final only = history.first;
      if (only.attachments == null || only.attachments!.isEmpty) {
        return o.ResponseInput.text(only.content);
      }
    }
    final items = <o.Item>[];
    for (final msg in history) {
      switch (msg.role) {
        case ChatRole.system:
          items.add(o.MessageItem.systemText(msg.content));
        case ChatRole.user:
          final attachments = msg.attachments ?? const [];
          if (attachments.isEmpty) {
            items.add(o.MessageItem.userText(msg.content));
          } else {
            final contents = <o.InputContent>[
              if (msg.content.isNotEmpty) o.InputContent.text(msg.content),
              for (final att in attachments)
                if (_responsesImageContent(att) case final c?) c,
            ];
            items.add(o.MessageItem.user(contents));
          }
        case ChatRole.assistant:
          if (msg.content.isEmpty) continue;
          items.add(o.MessageItem.assistantText(msg.content));
      }
    }
    return o.ResponseInput.items(items);
  }

  o.InputContent? _responsesImageContent(AiChatAttachment att) {
    final remote = att.remoteUrl;
    if (remote != null && remote.isNotEmpty) {
      return o.InputContent.imageUrl(remote);
    }
    final base64Data = att.base64Data;
    if (base64Data != null && base64Data.isNotEmpty) {
      return o.InputContent.imageUrl(
        'data:${att.mimeType};base64,$base64Data',
      );
    }
    final localPath = att.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      final bytes = File(localPath).readAsBytesSync();
      return o.InputContent.imageUrl(
        'data:${att.mimeType};base64,${base64Encode(bytes)}',
      );
    }
    return null;
  }

  // ────────────────────────── 消息转换：Gemini ──────────────────────────

  List<g.Content> _toGeminiContents(List<AiChatMessage> history) {
    final result = <g.Content>[];
    for (final msg in history) {
      switch (msg.role) {
        case ChatRole.system:
          // Gemini 用顶层 systemInstruction，跳过历史中的 system
          continue;
        case ChatRole.user:
          final parts = <g.Part>[
            if (msg.content.isNotEmpty) g.Part.text(msg.content),
            for (final att in msg.attachments ?? const [])
              if (_geminiImagePart(att) case final p?) p,
          ];
          if (parts.isEmpty) continue;
          result.add(g.Content(role: 'user', parts: parts));
        case ChatRole.assistant:
          if (msg.content.isEmpty) continue;
          result.add(
            g.Content(role: 'model', parts: [g.Part.text(msg.content)]),
          );
      }
    }
    return result;
  }

  g.Part? _geminiImagePart(AiChatAttachment att) {
    final base64Data = att.base64Data;
    if (base64Data != null && base64Data.isNotEmpty) {
      return g.Part.base64(base64Data, att.mimeType);
    }
    final localPath = att.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      final bytes = File(localPath).readAsBytesSync();
      return g.Part.bytes(bytes, att.mimeType);
    }
    final remote = att.remoteUrl;
    if (remote != null && remote.isNotEmpty) {
      // Gemini 不支持外链图片直传，需要先用 Files API 上传，本期降级为不带
      return null;
    }
    return null;
  }

  // ────────────────────────── 消息转换：Anthropic ──────────────────────────

  List<a.Message> _toAnthropicMessages(List<AiChatMessage> history) {
    final result = <a.Message>[];
    for (final msg in history) {
      switch (msg.role) {
        case ChatRole.system:
          continue;
        case ChatRole.user:
          result.add(
            a.Message(
              role: a.MessageRole.user,
              content: _toAnthropicContent(msg),
            ),
          );
        case ChatRole.assistant:
          if (msg.content.isEmpty) continue;
          result.add(
            a.Message(
              role: a.MessageRole.assistant,
              content: a.MessageContent.text(msg.content),
            ),
          );
      }
    }
    return result;
  }

  a.MessageContent _toAnthropicContent(AiChatMessage msg) {
    final attachments = msg.attachments;
    if (attachments == null || attachments.isEmpty) {
      return a.MessageContent.text(msg.content);
    }
    final blocks = <a.Block>[
      if (msg.content.isNotEmpty) a.Block.text(text: msg.content),
      for (final att in attachments)
        if (_anthropicImageBlock(att) case final block?) block,
    ];
    if (blocks.isEmpty) return a.MessageContent.text(msg.content);
    return a.MessageContent.blocks(blocks);
  }

  a.Block? _anthropicImageBlock(AiChatAttachment att) {
    final mediaType = _toAnthropicMediaType(att.mimeType);
    if (mediaType == null) return null;
    final remote = att.remoteUrl;
    if (remote != null && remote.isNotEmpty) {
      return a.Block.image(
        source: a.ImageBlockSource.urlImageSource(type: 'url', url: remote),
      );
    }
    final base64Data = att.base64Data;
    if (base64Data != null && base64Data.isNotEmpty) {
      return a.Block.image(
        source: a.ImageBlockSource.base64ImageSource(
          type: 'base64',
          mediaType: mediaType,
          data: base64Data,
        ),
      );
    }
    final localPath = att.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      final bytes = File(localPath).readAsBytesSync();
      return a.Block.image(
        source: a.ImageBlockSource.base64ImageSource(
          type: 'base64',
          mediaType: mediaType,
          data: base64Encode(bytes),
        ),
      );
    }
    return null;
  }

  a.Base64ImageSourceMediaType? _toAnthropicMediaType(String mime) {
    switch (mime.toLowerCase()) {
      case 'image/jpeg':
      case 'image/jpg':
        return a.Base64ImageSourceMediaType.imageJpeg;
      case 'image/png':
        return a.Base64ImageSourceMediaType.imagePng;
      case 'image/gif':
        return a.Base64ImageSourceMediaType.imageGif;
      case 'image/webp':
        return a.Base64ImageSourceMediaType.imageWebp;
    }
    return null;
  }

  // ────────────────────────── 错误映射 ──────────────────────────

  Exception _mapError(Object error) {
    final l10n = AiL10n.current;
    if (error is http.ClientException || error is SocketException) {
      return Exception(l10n.networkConnectionFailed);
    }
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return Exception(l10n.connectionTimeoutError);
        case DioExceptionType.connectionError:
          return Exception(l10n.cannotConnectError);
        case DioExceptionType.cancel:
          return Exception(l10n.requestCancelled);
        case DioExceptionType.badCertificate:
          return Exception(l10n.sslCertificateError);
        case DioExceptionType.badResponse:
          return Exception(_statusCodeMessage(error.response?.statusCode));
        case DioExceptionType.unknown:
          return Exception(l10n.unknownNetworkError);
      }
    }
    if (error is o.OpenAIException) {
      // openai_dart 4.x 的 ApiException 体系：按 HTTP status 给具体提示
      if (error is o.AuthenticationException) {
        return Exception(l10n.apiKeyInvalidError);
      }
      if (error is o.PermissionDeniedException) {
        return Exception(l10n.noAccessPermissionError);
      }
      if (error is o.NotFoundException) {
        return Exception(l10n.endpointNotFoundError);
      }
      if (error is o.RateLimitException) {
        return Exception(l10n.tooManyRequestsError);
      }
      if (error is o.BadRequestException) {
        // 400 通常含模型/参数级别的具体原因，把 OpenAI 原始 message 透出来
        return Exception(error.message);
      }
      if (error is o.InternalServerException) {
        return Exception(_serverErrorMessage(error.statusCode, error.message));
      }
      if (error is o.RequestTimeoutException) {
        return Exception(l10n.connectionTimeoutError);
      }
      if (error is o.ConnectionException) {
        return Exception(l10n.cannotConnectError);
      }
      // 兜底：包含 status 信息的通用错误
      return Exception(error.toString());
    }
    if (error is a.AnthropicClientException) {
      return Exception(error.message);
    }
    return Exception(error.toString());
  }

  /// 5xx 错误细分。代理服务器（one-api / aihubmix / 自建反代）转 OpenAI 时
  /// 经常返回 502/504，gpt-image 这种慢请求尤其容易触发。
  String _serverErrorMessage(int code, String? raw) {
    final l10n = AiL10n.current;
    switch (code) {
      case 502:
        return l10n.upstreamBadGatewayError;
      case 503:
        return l10n.upstreamUnavailableError;
      case 504:
        return l10n.upstreamGatewayTimeoutError;
    }
    return l10n.serverInternalError(code);
  }

  String _statusCodeMessage(int? code) {
    final l10n = AiL10n.current;
    switch (code) {
      case 401:
        return l10n.apiKeyInvalidError;
      case 403:
        return l10n.noAccessPermissionError;
      case 404:
        return l10n.endpointNotFoundError;
      case 429:
        return l10n.tooManyRequestsError;
    }
    if (code != null && code >= 500) return _serverErrorMessage(code, null);
    return l10n.requestFailed(code ?? 0);
  }

  // ────────────────────────── URL 处理 ──────────────────────────

  String _trimTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  /// googleai_dart 的 baseUrl 不应包含 `/v1beta` 路径，它会自己加。
  String _stripGeminiVersion(String url) {
    final trimmed = _trimTrailingSlash(url);
    for (final suffix in const ['/v1beta', '/v1']) {
      if (trimmed.endsWith(suffix)) {
        return trimmed.substring(0, trimmed.length - suffix.length);
      }
    }
    return trimmed;
  }
}
