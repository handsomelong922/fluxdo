import '../l10n/ai_l10n.dart';

/// 聊天角色
enum ChatRole { system, user, assistant }

/// 消息状态
enum MessageStatus { sending, streaming, completed, error }

/// AI 聊天消息
class AiChatMessage {
  final String id;
  final ChatRole role;
  final String content;
  final DateTime createdAt;
  final MessageStatus status;
  final String? errorMessage;

  const AiChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.status = MessageStatus.completed,
    this.errorMessage,
  });

  AiChatMessage copyWith({
    String? id,
    ChatRole? role,
    String? content,
    DateTime? createdAt,
    MessageStatus? status,
    String? errorMessage,
  }) {
    return AiChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.name,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'status': status.name,
      if (errorMessage != null) 'errorMessage': errorMessage,
    };
  }

  factory AiChatMessage.fromJson(Map<String, dynamic> json) {
    return AiChatMessage(
      id: json['id'] as String,
      role: ChatRole.values.byName(json['role'] as String),
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      status: MessageStatus.values.byName(json['status'] as String),
      errorMessage: json['errorMessage'] as String?,
    );
  }
}

/// AI 聊天会话（元数据）
class AiChatSession {
  final String id;
  final String? title;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AiChatSession({
    required this.id,
    this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  AiChatSession copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AiChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (title != null) 'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory AiChatSession.fromJson(Map<String, dynamic> json) {
    return AiChatSession(
      id: json['id'] as String,
      title: json['title'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

/// 话题会话组（用于历史列表展示）
class TopicSessionGroup {
  final int topicId;
  final String? topicTitle;
  final List<AiChatSession> sessions;

  const TopicSessionGroup({
    required this.topicId,
    this.topicTitle,
    required this.sessions,
  });
}

/// 上下文范围
enum ContextScope {
  firstPostOnly,
  first5,
  first10,
  first20,
  all;

  String get label {
    switch (this) {
      case ContextScope.firstPostOnly:
        return AiL10n.current.firstPostOnly;
      case ContextScope.first5:
        return AiL10n.current.first5Posts;
      case ContextScope.first10:
        return AiL10n.current.first10Posts;
      case ContextScope.first20:
        return AiL10n.current.first20Posts;
      case ContextScope.all:
        return AiL10n.current.allPosts;
    }
  }
}
