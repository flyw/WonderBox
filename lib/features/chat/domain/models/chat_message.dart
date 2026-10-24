import 'dart:convert';
import 'dart:io';

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
  final String? imagePath;
  final String? reasoning;
  final MessageStatus status;
  final String? errorMessage;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.imagePath,
    this.reasoning,
    this.status = MessageStatus.completed,
    this.errorMessage,
    required this.createdAt,
  });

  ChatMessage copyWith({
    String? id,
    MessageRole? role,
    String? content,
    String? imagePath,
    String? reasoning,
    MessageStatus? status,
    String? errorMessage,
    DateTime? createdAt,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      imagePath: imagePath ?? this.imagePath,
      reasoning: reasoning ?? this.reasoning,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toApiMessage() {
    if (imagePath != null && imagePath!.isNotEmpty) {
      final file = File(imagePath!);
      if (file.existsSync()) {
        try {
          final bytes = file.readAsBytesSync();
          final base64Image = base64Encode(bytes);
          return {
            'role': role.name,
            'content': [
              {
                'type': 'text',
                'text': content.isNotEmpty ? content : '（附带当前现场摄像头捕获画面）',
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/jpeg;base64,$base64Image',
                },
              },
            ],
          };
        } catch (_) {}
      }
    }
    return {
      'role': role.name,
      'content': content,
    };
  }
}
