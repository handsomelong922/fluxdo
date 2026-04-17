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

/// AI 模型
class AiModel {
  final String id;
  final String? name;
  final bool enabled;

  const AiModel({
    required this.id,
    this.name,
    this.enabled = true,
  });

  factory AiModel.fromJson(Map<String, dynamic> json) {
    return AiModel(
      id: json['id'] as String,
      name: json['name'] as String?,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (name != null) 'name': name,
      'enabled': enabled,
    };
  }

  AiModel copyWith({
    String? id,
    String? name,
    bool? enabled,
  }) {
    return AiModel(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
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
