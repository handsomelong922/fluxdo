/// AI 供应商类型
enum AiProviderType {
  openai('OpenAI', 'https://api.openai.com/v1'),
  openaiResponse('OpenAI-Response', 'https://api.openai.com/v1'),
  gemini('Gemini', 'https://generativelanguage.googleapis.com/v1beta'),
  anthropic('Anthropic', 'https://api.anthropic.com/v1');

  final String label;
  final String defaultBaseUrl;

  const AiProviderType(this.label, this.defaultBaseUrl);

  static AiProviderType? fromName(String? name) {
    if (name == null) return null;
    for (final type in values) {
      if (type.name == name) return type;
    }
    return null;
  }
}

/// 思考深度等级，统一映射到各供应商 API 参数。
enum ThinkingLevel { off, auto, low, medium, high, custom }

/// 思考配置：等级 + 自定义预算。
class ThinkingConfig {
  final ThinkingLevel level;
  final int customBudget;

  const ThinkingConfig({
    this.level = ThinkingLevel.off,
    this.customBudget = 8192,
  });

  bool get isEnabled => level != ThinkingLevel.off;

  ThinkingConfig copyWith({
    ThinkingLevel? level,
    int? customBudget,
  }) {
    return ThinkingConfig(
      level: level ?? this.level,
      customBudget: customBudget ?? this.customBudget,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'level': level.name,
      'customBudget': customBudget,
    };
  }

  factory ThinkingConfig.fromJson(Map<String, dynamic> json) {
    return ThinkingConfig(
      level: ThinkingLevel.values.byName(
        json['level'] as String? ?? ThinkingLevel.off.name,
      ),
      customBudget: json['customBudget'] as int? ?? 8192,
    );
  }
}

/// 联网搜索上下文规模。
enum AiWebSearchContextSize { low, medium, high }

/// 模型级能力配置。
///
/// 不同供应商的联网参数不兼容，因此只保存语义化配置，由
/// AiChatService 在发请求时按供应商类型转换。
class AiModelFeatureConfig {
  final bool webSearchEnabled;
  final AiWebSearchContextSize webSearchContextSize;
  final int webSearchMaxUses;
  final bool streamResponse;

  const AiModelFeatureConfig({
    this.webSearchEnabled = false,
    this.webSearchContextSize = AiWebSearchContextSize.medium,
    this.webSearchMaxUses = 5,
    this.streamResponse = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'web_search_enabled': webSearchEnabled,
      'web_search_context_size': webSearchContextSize.name,
      'web_search_max_uses': webSearchMaxUses,
      'stream_response': streamResponse,
    };
  }

  factory AiModelFeatureConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AiModelFeatureConfig();
    final rawContextSize = json['web_search_context_size'] as String?;
    return AiModelFeatureConfig(
      webSearchEnabled: json['web_search_enabled'] as bool? ?? false,
      webSearchContextSize: AiWebSearchContextSize.values.firstWhere(
        (size) => size.name == rawContextSize,
        orElse: () => AiWebSearchContextSize.medium,
      ),
      webSearchMaxUses: _clampWebSearchMaxUses(
        json['web_search_max_uses'] as int? ?? 5,
      ),
      streamResponse: json['stream_response'] as bool? ?? true,
    );
  }

  AiModelFeatureConfig copyWith({
    bool? webSearchEnabled,
    AiWebSearchContextSize? webSearchContextSize,
    int? webSearchMaxUses,
    bool? streamResponse,
  }) {
    return AiModelFeatureConfig(
      webSearchEnabled: webSearchEnabled ?? this.webSearchEnabled,
      webSearchContextSize: webSearchContextSize ?? this.webSearchContextSize,
      webSearchMaxUses: webSearchMaxUses != null
          ? _clampWebSearchMaxUses(webSearchMaxUses)
          : this.webSearchMaxUses,
      streamResponse: streamResponse ?? this.streamResponse,
    );
  }

  static int _clampWebSearchMaxUses(int value) => value.clamp(1, 10);
}

/// AI 模型
class AiModel {
  final String id;
  final String? name;
  final bool enabled;
  final AiModelFeatureConfig features;

  const AiModel({
    required this.id,
    this.name,
    this.enabled = true,
    this.features = const AiModelFeatureConfig(),
  });

  factory AiModel.fromJson(Map<String, dynamic> json) {
    return AiModel(
      id: json['id'] as String,
      name: json['name'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      features: AiModelFeatureConfig.fromJson(
        json['features'] as Map<String, dynamic>?,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (name != null) 'name': name,
      'enabled': enabled,
      'features': features.toJson(),
    };
  }

  AiModel copyWith({
    String? id,
    String? name,
    bool? enabled,
    AiModelFeatureConfig? features,
  }) {
    return AiModel(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      features: features ?? this.features,
    );
  }
}

/// AI 供应商
class AiProvider {
  final String id;
  final String name;
  final AiProviderType type;
  final String baseUrl;
  final List<AiModel> models;

  const AiProvider({
    required this.id,
    required this.name,
    required this.type,
    required this.baseUrl,
    this.models = const [],
  });

  factory AiProvider.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String?;
    final type = AiProviderType.fromName(typeStr) ?? AiProviderType.openai;
    return AiProvider(
      id: json['id'] as String,
      name: json['name'] as String,
      type: type,
      baseUrl: json['base_url'] as String? ?? type.defaultBaseUrl,
      models: (json['models'] as List<dynamic>?)
              ?.map((e) => AiModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'base_url': baseUrl,
      'models': models.map((m) => m.toJson()).toList(),
    };
  }

  AiProvider copyWith({
    String? id,
    String? name,
    AiProviderType? type,
    String? baseUrl,
    List<AiModel>? models,
  }) {
    return AiProvider(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      baseUrl: baseUrl ?? this.baseUrl,
      models: models ?? this.models,
    );
  }
}
