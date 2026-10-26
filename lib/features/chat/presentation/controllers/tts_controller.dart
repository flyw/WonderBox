import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/tts_service.dart';

class TtsState {
  final bool isSpeaking;
  final String? currentSpeakingMessageId;
  final bool isAutoSpeakEnabled;

  const TtsState({
    this.isSpeaking = false,
    this.currentSpeakingMessageId,
    this.isAutoSpeakEnabled = true,
  });

  TtsState copyWith({
    bool? isSpeaking,
    String? currentSpeakingMessageId,
    bool? isAutoSpeakEnabled,
  }) {
    return TtsState(
      isSpeaking: isSpeaking ?? this.isSpeaking,
      currentSpeakingMessageId: currentSpeakingMessageId,
      isAutoSpeakEnabled: isAutoSpeakEnabled ?? this.isAutoSpeakEnabled,
    );
  }
}

class TtsNotifier extends Notifier<TtsState> {
  late final TtsService _service;

  @override
  TtsState build() {
    _service = ref.watch(ttsServiceProvider);
    _service.onSpeakingChanged = (speaking) {
      state = state.copyWith(
        isSpeaking: speaking,
        currentSpeakingMessageId: speaking ? state.currentSpeakingMessageId : null,
      );
    };
    return const TtsState();
  }

  void toggleAutoSpeak() {
    final next = !state.isAutoSpeakEnabled;
    state = state.copyWith(isAutoSpeakEnabled: next);
    if (!next) {
      _service.stop();
    }
  }

  Future<void> speakMessage({required String messageId, required String text}) async {
    if (state.isSpeaking && state.currentSpeakingMessageId == messageId) {
      await _service.stop();
      state = state.copyWith(isSpeaking: false, currentSpeakingMessageId: null);
      return;
    }
    state = state.copyWith(isSpeaking: true, currentSpeakingMessageId: messageId);
    await _service.speak(text);
  }

  Future<void> autoSpeak(String text) async {
    if (!state.isAutoSpeakEnabled) return;
    state = state.copyWith(isSpeaking: true);
    await _service.speak(text);
  }

  Future<void> stop() async {
    await _service.stop();
    state = state.copyWith(isSpeaking: false, currentSpeakingMessageId: null);
  }
}

final ttsControllerProvider = NotifierProvider<TtsNotifier, TtsState>(TtsNotifier.new);
