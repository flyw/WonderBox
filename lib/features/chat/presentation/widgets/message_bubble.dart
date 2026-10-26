import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../../domain/models/chat_message.dart';
import '../controllers/tts_controller.dart';
import 'reasoning_foldout.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == MessageRole.user;
    final isStreaming = message.status == MessageStatus.streaming;
    final hasError = message.status == MessageStatus.error;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                CircleAvatar(
                  radius: 16,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(Icons.auto_awesome, size: 16, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.85,
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: isUser ? 16 : 14,
                    vertical: isUser ? 10 : 12,
                  ),
                  decoration: BoxDecoration(
                    color: isUser
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isUser ? 18 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Camera snapshot preview if attached
                      if (message.imagePath != null && message.imagePath!.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              children: [
                                Image.file(
                                  File(message.imagePath!),
                                  width: 220,
                                  height: 140,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                                ),
                                Positioned(
                                  left: 6,
                                  bottom: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.65),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.camera_alt, size: 10, color: Colors.white),
                                        SizedBox(width: 4),
                                        Text(
                                          '现场画面捕获',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      // Reasoning / CoT thinking box
                      if (message.reasoning != null && message.reasoning!.isNotEmpty)
                        ReasoningFoldout(
                          reasoning: message.reasoning!,
                          isStreaming: isStreaming && message.content.isEmpty,
                        ),

                      // Streaming indicator when starting
                      if (isStreaming && message.content.isEmpty && (message.reasoning == null || message.reasoning!.isEmpty))
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: isUser ? theme.colorScheme.onPrimary : theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Thinking...',
                              style: TextStyle(
                                fontSize: 13,
                                color: isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        )
                      else if (isUser)
                        SelectableText(
                          message.content,
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        )
                      else
                        GptMarkdown(
                          message.content,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 15,
                            height: 1.45,
                          ),
                        ),

                      // Error message if failed
                      if (hasError && message.errorMessage != null)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  message.errorMessage!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (isUser) ...[
                const SizedBox(width: 10),
                CircleAvatar(
                  radius: 16,
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  child: Icon(Icons.person, size: 16, color: theme.colorScheme.secondary),
                ),
              ],
            ],
          ),

          // Message action footer (TTS speak and copy buttons)
          if (!isUser && message.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 42, top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Consumer(
                    builder: (context, ref, _) {
                      final ttsState = ref.watch(ttsControllerProvider);
                      final isThisSpeaking =
                          ttsState.isSpeaking && ttsState.currentSpeakingMessageId == message.id;
                      return IconButton(
                        icon: Icon(
                          isThisSpeaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
                          size: 16,
                          color: isThisSpeaking ? theme.colorScheme.primary : Colors.grey.shade600,
                        ),
                        tooltip: isThisSpeaking ? '停止朗读' : '语音朗读',
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(6),
                        onPressed: () {
                          ref.read(ttsControllerProvider.notifier).speakMessage(
                                messageId: message.id,
                                text: message.content,
                              );
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 14),
                    color: Colors.grey.shade600,
                    tooltip: 'Copy message',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(6),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: message.content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已复制到剪贴板'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
