enum MessageRole {
  user,
  assistant,
  system,
}

enum MessageStatus {
  idle,
  streaming,
  completed,
  error,
}

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final String? reasoning;
  final MessageStatus status;
  final String? errorMessage;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.reasoning,
    this.status = MessageStatus.completed,
    this.errorMessage,
    required this.createdAt,
  });

  ChatMessage copyWith({
    String? id,
    MessageRole? role,
    String? content,
    String? reasoning,
    MessageStatus? status,
    String? errorMessage,
    DateTime? createdAt,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      reasoning: reasoning ?? this.reasoning,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toApiMessage() {
    return {
      'role': role.name,
      'content': content,
    };
  }
}
