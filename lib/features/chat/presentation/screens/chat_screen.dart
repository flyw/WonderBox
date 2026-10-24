import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/ambient_assistant_controller.dart';
import '../controllers/chat_controller.dart';
import '../widgets/ambient_listening_pill.dart';
import '../widgets/chat_input_box.dart';
import '../widgets/message_bubble.dart';
import '../widgets/config_sheet.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ambientAssistantProvider.notifier).startAmbientListening();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatControllerProvider);
    final config = ref.watch(llmConfigProvider);
    final theme = Theme.of(context);

    // Auto scroll when messages update
    ref.listen(chatControllerProvider, (prev, next) {
      if (prev?.messages.length != next.messages.length ||
          next.isStreaming) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('WonderBox AI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(
              '${config.model} (${config.apiKey.isEmpty ? "No Key" : "Ready"})',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: AmbientListeningPill(),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Model Settings',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => const ConfigSheet(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear Chat',
            onPressed: chatState.messages.isEmpty
                ? null
                : () {
                    ref.read(chatControllerProvider.notifier).clearChat();
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          const AmbientStatusBar(),
          Expanded(
            child: chatState.messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 48,
                            color: theme.colorScheme.primary.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'SOTA LLM Architecture Ready',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Click the settings icon in the top right to configure your API Key.\nSupports DeepSeek (V3 & R1 Reasoning), OpenAI, Ollama, etc.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.tune),
                            label: const Text('Configure Provider'),
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                builder: (_) => const ConfigSheet(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: chatState.messages.length,
                    itemBuilder: (context, index) {
                      final message = chatState.messages[index];
                      return MessageBubble(key: ValueKey(message.id), message: message);
                    },
                  ),
          ),
          ChatInputBox(
            isStreaming: chatState.isStreaming,
            onSend: (text) {
              ref.read(chatControllerProvider.notifier).sendMessage(text);
            },
            onStop: () {
              ref.read(chatControllerProvider.notifier).stopStreaming();
            },
          ),
        ],
      ),
    );
  }
}
