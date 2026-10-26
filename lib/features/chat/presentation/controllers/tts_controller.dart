import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/tts_service.dart';

class TtsState {
  final bool isSpeaking;
  final String? currentSpeakingMessageId;
  final bool isAutoSpeakEnabled;
  final String? selectedVoiceId;
  final String? selectedVoiceName;
  final double rate;
  final double pitch;
  final List<Map<String, dynamic>> availableVoices;

  const TtsState({
    this.isSpeaking = false,
    this.currentSpeakingMessageId,
    this.isAutoSpeakEnabled = true,
    this.selectedVoiceId,
    this.selectedVoiceName,
    this.rate = 0.5,
    this.pitch = 1.0,
    this.availableVoices = const [],
  });

  TtsState copyWith({
    bool? isSpeaking,
    String? currentSpeakingMessageId,
    bool? isAutoSpeakEnabled,
    String? selectedVoiceId,
    String? selectedVoiceName,
    double? rate,
    double? pitch,
    List<Map<String, dynamic>>? availableVoices,
  }) {
    return TtsState(
      isSpeaking: isSpeaking ?? this.isSpeaking,
      currentSpeakingMessageId: currentSpeakingMessageId,
      isAutoSpeakEnabled: isAutoSpeakEnabled ?? this.isAutoSpeakEnabled,
      selectedVoiceId: selectedVoiceId ?? this.selectedVoiceId,
      selectedVoiceName: selectedVoiceName ?? this.selectedVoiceName,
      rate: rate ?? this.rate,
      pitch: pitch ?? this.pitch,
      availableVoices: availableVoices ?? this.availableVoices,
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

    // Load available iOS voices asynchronously
    Future.microtask(() => loadAvailableVoices());

    return const TtsState();
  }

  Future<void> loadAvailableVoices() async {
    final voices = await _service.getAvailableVoices();
    String? targetId = state.selectedVoiceId;
    String? targetName = state.selectedVoiceName;

    if (targetId == null && voices.isNotEmpty) {
      // Find Siri high-fidelity or premium voice first
      final siriVoice = voices.firstWhere(
        (v) =>
            ((v['name'] as String? ?? '').toLowerCase().contains('siri') ||
                (v['identifier'] as String? ?? '').toLowerCase().contains('siri')) &&
            ((v['quality'] as int? ?? 0) >= 2),
        orElse: () => voices.firstWhere(
          (v) =>
              (v['name'] as String? ?? '').toLowerCase().contains('siri') ||
              (v['identifier'] as String? ?? '').toLowerCase().contains('siri'),
          orElse: () => voices.firstWhere(
            (v) => (v['quality'] as int? ?? 0) >= 2,
            orElse: () => voices.first,
          ),
        ),
      );
      targetId = siriVoice['identifier'] as String?;
      targetName = siriVoice['name'] as String?;
    }

    state = state.copyWith(
      availableVoices: voices,
      selectedVoiceId: targetId,
      selectedVoiceName: targetName,
    );
  }

  void selectVoice(String voiceId, String name) {
    state = state.copyWith(
      selectedVoiceId: voiceId,
      selectedVoiceName: name,
    );
  }

  void setRate(double rate) {
    state = state.copyWith(rate: rate);
  }

  void setPitch(double pitch) {
    state = state.copyWith(pitch: pitch);
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
    await _service.speak(
      text,
      rate: state.rate,
      pitch: state.pitch,
      voiceIdentifier: state.selectedVoiceId,
    );
  }

  Future<void> autoSpeak(String text) async {
    if (!state.isAutoSpeakEnabled) return;
    state = state.copyWith(isSpeaking: true);
    await _service.speak(
      text,
      rate: state.rate,
      pitch: state.pitch,
      voiceIdentifier: state.selectedVoiceId,
    );
  }

  Future<void> stop() async {
    await _service.stop();
    state = state.copyWith(isSpeaking: false, currentSpeakingMessageId: null);
  }
}

final ttsControllerProvider = NotifierProvider<TtsNotifier, TtsState>(TtsNotifier.new);
