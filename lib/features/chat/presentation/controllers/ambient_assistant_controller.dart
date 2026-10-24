import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/local_minicpm_service.dart';
import '../../domain/services/topic_relevance_judge.dart';
import '../controllers/chat_controller.dart';
import '../../../voice/data/datasources/ambient_voice_service.dart';

class AmbientAssistantState {
  final bool isEnabled;
  final bool isListening;
  final bool isSpeechActive;
  final String liveText;
  final String statusMessage;
  final String? lastTranscribedPhrase;
  final String? lastDecision;
  final String? errorMessage;

  const AmbientAssistantState({
    this.isEnabled = false,
    this.isListening = false,
    this.isSpeechActive = false,
    this.liveText = '',
    this.statusMessage = '伴听模式待启动',
    this.lastTranscribedPhrase,
    this.lastDecision,
    this.errorMessage,
  });

  AmbientAssistantState copyWith({
    bool? isEnabled,
    bool? isListening,
    bool? isSpeechActive,
    String? liveText,
    String? statusMessage,
    String? lastTranscribedPhrase,
    String? lastDecision,
    String? errorMessage,
  }) {
    return AmbientAssistantState(
      isEnabled: isEnabled ?? this.isEnabled,
      isListening: isListening ?? this.isListening,
      isSpeechActive: isSpeechActive ?? this.isSpeechActive,
      liveText: liveText ?? this.liveText,
      statusMessage: statusMessage ?? this.statusMessage,
      lastTranscribedPhrase: lastTranscribedPhrase ?? this.lastTranscribedPhrase,
      lastDecision: lastDecision ?? this.lastDecision,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class AmbientAssistantNotifier extends Notifier<AmbientAssistantState> {
  @override
  AmbientAssistantState build() {
    final service = ref.read(ambientVoiceServiceProvider);
    ref.onDispose(() {
      service.stopListening();
    });
    return const AmbientAssistantState();
  }

  Future<void> startAmbientListening() async {
    final service = ref.read(ambientVoiceServiceProvider);
    state = state.copyWith(
      isEnabled: true,
      statusMessage: '正在准备 TEN VAD 与语音模型...',
      errorMessage: null,
    );

    // Pre-warm local MiniCPM-V-4.6 engine in background
    ref.read(localMiniCpmServiceProvider).startServerIfNeeded();

    final success = await service.startListening(
      onSpeechDetectedChanged: (isDetected) {
        state = state.copyWith(
          isSpeechActive: isDetected,
          statusMessage: isDetected ? '正在聆听发言...' : 'TEN VAD 伴听中 (静候短句)',
        );
      },
      onLiveText: (text) {
        state = state.copyWith(
          liveText: text,
          isSpeechActive: true,
          statusMessage: '🎙️ 正在聆听: "$text"',
        );
      },
      onPhraseTranscribed: (phrase) {
        _handlePhraseTranscribed(phrase);
      },
      onError: (err) {
        state = state.copyWith(
          isListening: false,
          statusMessage: '伴听异常',
          errorMessage: err,
        );
      },
    );

    if (success) {
      state = state.copyWith(
        isListening: true,
        liveText: '',
        statusMessage: 'TEN VAD 伴听就绪 (开口自动分析)',
        errorMessage: null,
      );
    } else {
      state = state.copyWith(
        isListening: false,
        statusMessage: state.errorMessage ?? '伴听启动失败',
      );
    }
  }

  Future<void> stopAmbientListening() async {
    final service = ref.read(ambientVoiceServiceProvider);
    await service.stopListening();
    state = state.copyWith(
      isEnabled: false,
      isListening: false,
      isSpeechActive: false,
      liveText: '',
      statusMessage: '伴听已暂停',
    );
  }

  Future<void> toggleAmbientListening() async {
    if (state.isListening) {
      await stopAmbientListening();
    } else {
      await startAmbientListening();
    }
  }

  Future<void> _handlePhraseTranscribed(String phrase) async {
    state = state.copyWith(
      liveText: '',
      lastTranscribedPhrase: phrase,
      statusMessage: '⚖️ Jev-Style-0.8B 正在判别: "$phrase"...',
    );

    final chatState = ref.read(chatControllerProvider);
    final config = ref.read(llmConfigProvider);
    final judge = ref.read(topicRelevanceJudgeProvider);

    final isRelevant = await judge.judgeRelevance(
      candidatePhrase: phrase,
      conversationHistory: chatState.messages,
      config: config,
    );

    if (isRelevant) {
      state = state.copyWith(
        lastDecision: 'relevant',
        statusMessage: '✅ Jev-Style 判定相关，MiniCPM-V-4.6 正在端侧分析: "$phrase"',
      );
      // Automatically inject user message and trigger LLM analysis
      await ref.read(chatControllerProvider.notifier).sendMessage(phrase);
      if (state.isListening) {
        state = state.copyWith(
          statusMessage: 'TEN VAD 伴听就绪 (开口自动分析)',
        );
      }
    } else {
      state = state.copyWith(
        lastDecision: 'ignored',
        statusMessage: '🛡️ Jev-Style 判定为非相关闲聊，已过滤: "$phrase"',
      );
    }
  }
}

final ambientAssistantProvider =
    NotifierProvider<AmbientAssistantNotifier, AmbientAssistantState>(
  AmbientAssistantNotifier.new,
);
