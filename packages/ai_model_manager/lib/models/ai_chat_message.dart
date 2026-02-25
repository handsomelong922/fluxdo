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
}

/// 上下文范围
enum ContextScope {
  firstPostOnly('仅主帖'),
  first5('前 5 楼'),
  first10('前 10 楼'),
  first20('前 20 楼'),
  all('全部帖子');

  final String label;
  const ContextScope(this.label);
}
