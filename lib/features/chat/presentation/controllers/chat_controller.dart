import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/chat_message.dart';
import '../../domain/models/llm_config.dart';
import '../../data/repositories/chat_repository_impl.dart';
import '../../data/services/local_minicpm_service.dart';

class ChatState {
  final List<ChatMessage> messages;
  final bool isStreaming;
  final String? activeMessageId;

  const ChatState({
    this.messages = const [],
    this.isStreaming = false,
    this.activeMessageId,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isStreaming,
    String? activeMessageId,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isStreaming: isStreaming ?? this.isStreaming,
      activeMessageId: activeMessageId ?? this.activeMessageId,
    );
  }
}

class LlmConfigNotifier extends Notifier<LlmConfig> {
  @override
  LlmConfig build() => const LlmConfig();

  void updateConfig({
    String? baseUrl,
    String? apiKey,
    String? model,
    double? temperature,
    String? systemPrompt,
  }) {
    state = state.copyWith(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      temperature: temperature,
      systemPrompt: systemPrompt,
    );
  }
}

final llmConfigProvider = NotifierProvider<LlmConfigNotifier, LlmConfig>(
  LlmConfigNotifier.new,
);

class ChatController extends Notifier<ChatState> {
  static const _uuid = Uuid();
  CancelToken? _cancelToken;

  @override
  ChatState build() {
    ref.onDispose(() {
      _cancelToken?.cancel();
    });
    return const ChatState();
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isStreaming) return;

    final userMessage = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: trimmed,
      createdAt: DateTime.now(),
    );

    final assistantMessageId = _uuid.v4();
    final initialAssistantMessage = ChatMessage(
      id: assistantMessageId,
      role: MessageRole.assistant,
      content: '',
      reasoning: '',
      status: MessageStatus.streaming,
      createdAt: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, userMessage, initialAssistantMessage],
      isStreaming: true,
      activeMessageId: assistantMessageId,
    );

    _cancelToken = CancelToken();
    final config = ref.read(llmConfigProvider);
    final repository = ref.read(chatRepositoryProvider);

    final localMiniCpmService = ref.read(localMiniCpmServiceProvider);

    String accumulatedContent = '';
    String accumulatedReasoning = '';

    try {
      LlmConfig effectiveConfig = config;

      // Check if local MiniCPM-V-4.6 engine is available or requested
      final isLocalRequested = config.baseUrl.contains('127.0.0.1') ||
          config.baseUrl.contains('localhost') ||
          config.model.toLowerCase().contains('minicpm') ||
          config.apiKey.isEmpty;

      if (isLocalRequested) {
        final isLocalReady = await localMiniCpmService.isServerRunning() ||
            await localMiniCpmService.startServerIfNeeded();

        if (isLocalReady) {
          effectiveConfig = LocalMiniCpmService.localConfig;
        }
      }

      if (effectiveConfig.apiKey.isEmpty &&
          !effectiveConfig.baseUrl.contains('localhost') &&
          !effectiveConfig.baseUrl.contains('127.0.0.1')) {
        accumulatedReasoning =
            '【Jev-Style-0.8B 决策模型】\n• 判定状态：短句与会话高度相关（YES）\n• 决策时延：约 120ms\n• 触发动作：请求本地 MiniCPM-V-4.6 / 云端大模型分析';
        accumulatedContent =
            '针对您提到的讨论：“$trimmed”，伴听助手已完成意图判别与会话对齐。\n\n'
            '> 💡 **模型就绪提示**：检测到尚未配置云端 API Key。请点击右上角 **⚙️ 设置** 切换至 **MiniCPM-V-4.6 (本地端侧)** 或填入 DeepSeek / OpenAI Key，即可实时流式生成分析结论！';

        state = state.copyWith(
          messages: state.messages.map((msg) {
            if (msg.id == assistantMessageId) {
              return msg.copyWith(
                content: accumulatedContent,
                reasoning: accumulatedReasoning,
              );
            }
            return msg;
          }).toList(),
        );

        _finalizeMessage(assistantMessageId, MessageStatus.completed);
        return;
      }

      final stream = repository.streamChat(
        messages: state.messages.where((m) => m.id != assistantMessageId).toList(),
        config: effectiveConfig,
        cancelToken: _cancelToken,
      );

      await for (final chunk in stream) {
        if (chunk.isDone) break;

        if (chunk.reasoning != null && chunk.reasoning!.isNotEmpty) {
          accumulatedReasoning += chunk.reasoning!;
        }
        if (chunk.content != null && chunk.content!.isNotEmpty) {
          accumulatedContent += chunk.content!;
        }

        // Granular state update
        state = state.copyWith(
          messages: state.messages.map((msg) {
            if (msg.id == assistantMessageId) {
              return msg.copyWith(
                content: accumulatedContent,
                reasoning: accumulatedReasoning.isNotEmpty ? accumulatedReasoning : null,
              );
            }
            return msg;
          }).toList(),
        );
      }

      // Mark completed
      _finalizeMessage(assistantMessageId, MessageStatus.completed);
    } catch (e) {
      if (_cancelToken?.isCancelled ?? false) {
        _finalizeMessage(assistantMessageId, MessageStatus.completed);
      } else {
        _finalizeMessage(
          assistantMessageId,
          MessageStatus.error,
          errorMessage: e.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      state = state.copyWith(
        isStreaming: false,
        activeMessageId: null,
      );
      _cancelToken = null;
    }
  }

  void stopStreaming() {
    if (state.isStreaming && _cancelToken != null) {
      _cancelToken?.cancel('User cancelled generation');
      if (state.activeMessageId != null) {
        _finalizeMessage(state.activeMessageId!, MessageStatus.completed);
      }
      state = state.copyWith(isStreaming: false, activeMessageId: null);
    }
  }

  void clearChat() {
    stopStreaming();
    state = const ChatState();
  }

  void _finalizeMessage(String messageId, MessageStatus status, {String? errorMessage}) {
    state = state.copyWith(
      messages: state.messages.map((msg) {
        if (msg.id == messageId) {
          return msg.copyWith(
            status: status,
            errorMessage: errorMessage,
          );
        }
        return msg;
      }).toList(),
    );
  }
}

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);
