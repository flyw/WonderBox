import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/local_minicpm_service.dart';
import '../../domain/services/topic_relevance_judge.dart';
import '../controllers/chat_controller.dart';
import '../controllers/tts_controller.dart';
import '../../../camera/presentation/controllers/camera_controller.dart';
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
  // Acoustic & VAD Diagnostics
  final double currentRms;
  final bool isEnergySufficient;
  final double minRmsThreshold;
  final double vadThreshold;
  final double minSpeechDuration;
  final double distanceRatio; // 0.0 (10cm 贴身) ~ 1.0 (3m 远场)

  const AmbientAssistantState({
    this.isEnabled = false,
    this.isListening = false,
    this.isSpeechActive = false,
    this.liveText = '',
    this.statusMessage = '伴听模式待启动',
    this.lastTranscribedPhrase,
    this.lastDecision,
    this.errorMessage,
    this.currentRms = 0.0,
    this.isEnergySufficient = false,
    this.minRmsThreshold = 0.008,
    this.vadThreshold = 0.40,
    this.minSpeechDuration = 0.18,
    this.distanceRatio = 0.45,
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
    double? currentRms,
    bool? isEnergySufficient,
    double? minRmsThreshold,
    double? vadThreshold,
    double? minSpeechDuration,
    double? distanceRatio,
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
      currentRms: currentRms ?? this.currentRms,
      isEnergySufficient: isEnergySufficient ?? this.isEnergySufficient,
      minRmsThreshold: minRmsThreshold ?? this.minRmsThreshold,
      vadThreshold: vadThreshold ?? this.vadThreshold,
      minSpeechDuration: minSpeechDuration ?? this.minSpeechDuration,
      distanceRatio: distanceRatio ?? this.distanceRatio,
    );
  }
}

class AmbientAssistantNotifier extends Notifier<AmbientAssistantState> {
  int _lastRmsTimestamp = 0;

  @override
  AmbientAssistantState build() {
    final service = ref.read(ambientVoiceServiceProvider);
    ref.onDispose(() {
      service.stopListening();
    });

    // Auto mute ambient listening while streaming response or speaking via TTS
    ref.listen(chatControllerProvider.select((s) => s.isStreaming), (prev, isStreaming) {
      _syncMuteState();
    });

    ref.listen(ttsControllerProvider.select((s) => s.isSpeaking), (prev, isSpeaking) {
      _syncMuteState();
    });

    return AmbientAssistantState(
      minRmsThreshold: service.minRmsThreshold,
      vadThreshold: service.vadThreshold,
      minSpeechDuration: service.minSpeechDuration,
    );
  }

  void updateVadConfig({
    double? vadThreshold,
    double? minRmsThreshold,
    double? minSpeechDuration,
  }) {
    final service = ref.read(ambientVoiceServiceProvider);
    service.updateConfig(
      vadThreshold: vadThreshold,
      minRmsThreshold: minRmsThreshold,
      minSpeechDuration: minSpeechDuration,
    );
    state = state.copyWith(
      vadThreshold: vadThreshold ?? state.vadThreshold,
      minRmsThreshold: minRmsThreshold ?? state.minRmsThreshold,
      minSpeechDuration: minSpeechDuration ?? state.minSpeechDuration,
    );
  }

  /// Sets the VAD listening distance axis continuously:
  /// ratio: 0.0 (10cm 贴近) ~ 0.45 (45cm 桌面推荐) ~ 1.0 (2.5m+ 远场全开)
  void setDistanceRatio(double ratio) {
    final clamped = ratio.clamp(0.0, 1.0);
    double rms;
    double vad;
    double minSpeech;

    if (clamped <= 0.45) {
      final t = clamped / 0.45;
      rms = 0.024 + (0.008 - 0.024) * t;
      vad = 0.50 + (0.40 - 0.50) * t;
      minSpeech = 0.25 + (0.18 - 0.25) * t;
    } else {
      final t = (clamped - 0.45) / 0.55;
      rms = 0.008 + (0.002 - 0.008) * t;
      vad = 0.40 + (0.32 - 0.40) * t;
      minSpeech = 0.18 + (0.10 - 0.18) * t;
    }

    final service = ref.read(ambientVoiceServiceProvider);
    service.updateConfig(
      vadThreshold: vad,
      minRmsThreshold: rms,
      minSpeechDuration: minSpeech,
    );
    state = state.copyWith(
      distanceRatio: clamped,
      vadThreshold: vad,
      minRmsThreshold: rms,
      minSpeechDuration: minSpeech,
    );
  }

  void _syncMuteState() {
    final isStreaming = ref.read(chatControllerProvider).isStreaming;
    final isSpeaking = ref.read(ttsControllerProvider).isSpeaking;
    final shouldMute = isStreaming || isSpeaking;
    final service = ref.read(ambientVoiceServiceProvider);

    if (state.isListening) {
      service.setMuted(shouldMute);
      if (shouldMute) {
        state = state.copyWith(
          isSpeechActive: false,
          liveText: '',
          statusMessage: isSpeaking
              ? '🔊 正在语音播报 (说完后继续伴听)'
              : '🤖 MiniCPM-V 正在思考回答...',
        );
      } else {
        state = state.copyWith(
          isSpeechActive: false,
          liveText: '',
          statusMessage: 'TEN VAD 伴听就绪 (开口自动分析)',
        );
      }
    }
  }

  Future<void> startAmbientListening() async {
    final service = ref.read(ambientVoiceServiceProvider);
    state = state.copyWith(
      isEnabled: true,
      statusMessage: '正在准备 TEN VAD 与语音模型...',
      errorMessage: null,
    );

    // Pre-warm local MiniCPM-V-4.6 engine and camera in background
    ref.read(localMiniCpmServiceProvider).startServerIfNeeded();
    ref.read(cameraControllerProvider.notifier).initialize();

    final success = await service.startListening(
      onSpeechDetectedChanged: (isDetected) {
        if (service.isMuted) return;
        state = state.copyWith(
          isSpeechActive: isDetected,
          statusMessage: isDetected ? '正在聆听发言...' : 'TEN VAD 伴听中 (静候短句)',
        );
      },
      onRmsChanged: (rms, isSufficient) {
        if (service.isMuted) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastRmsTimestamp > 120) {
          _lastRmsTimestamp = now;
          state = state.copyWith(
            currentRms: rms,
            isEnergySufficient: isSufficient,
          );
        }
      },
      onLiveText: (text) {
        if (service.isMuted) return;
        state = state.copyWith(
          liveText: text,
          isSpeechActive: true,
          statusMessage: '🎙️ 正在聆听: "$text"',
        );
      },
      onPhraseTranscribed: (phrase) {
        if (service.isMuted) return;
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
    final chatState = ref.read(chatControllerProvider);
    final ttsState = ref.read(ttsControllerProvider);
    if (chatState.isStreaming || ttsState.isSpeaking) {
      debugPrint('[AmbientAssistant] Assistant is actively streaming or speaking, skipping phrase: "$phrase"');
      return;
    }

    state = state.copyWith(
      liveText: '',
      lastTranscribedPhrase: phrase,
      statusMessage: '⚖️ Jev-Style-0.8B 正在判别: "$phrase"...',
    );

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
        statusMessage: '📸 Jev-Style 判定相关，正在读取现场画面...',
      );

      // Read camera frame if camera is enabled
      String? snapshotPath;
      try {
        snapshotPath = await ref.read(cameraControllerProvider.notifier).captureFrame();
      } catch (e) {
        debugPrint('[AmbientAssistant] Camera frame capture error: $e');
      }

      state = state.copyWith(
        statusMessage: snapshotPath != null
            ? '📸 画面已读取，MiniCPM-V-4.6 正在端侧多模态分析: "$phrase"'
            : '✅ Jev-Style 判定相关，MiniCPM-V-4.6 正在端侧分析: "$phrase"',
      );

      // Automatically inject user message with captured image and trigger LLM analysis
      await ref.read(chatControllerProvider.notifier).sendMessage(
        phrase,
        imagePath: snapshotPath,
      );

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
