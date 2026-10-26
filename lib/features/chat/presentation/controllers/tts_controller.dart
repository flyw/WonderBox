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

    bool isSiriVoice4(Map<String, dynamic> v) {
      final name = (v['name'] as String? ?? '').toLowerCase();
      final id = (v['identifier'] as String? ?? '').toLowerCase();
      final lang = (v['language'] as String? ?? '').toLowerCase();
      final isEn = lang.startsWith('en');
      final is4 = name.contains('voice 4') ||
          name.contains('声音 4') ||
          name.contains('voice4') ||
          id.contains('voice_4') ||
          id.contains('voice4') ||
          id.contains('voice-4') ||
          ((name.contains('siri') || id.contains('siri')) &&
              (name.contains('4') || id.contains('4')));
      return isEn && is4;
    }

    bool isFemale(Map<String, dynamic> v) {
      final name = (v['name'] as String? ?? '').toLowerCase();
      final id = (v['identifier'] as String? ?? '').toLowerCase();
      final gender = v['gender'] as int? ?? 0;
      return gender == 2 ||
          id.contains('female') ||
          id.contains('ting-ting') ||
          id.contains('tingting') ||
          id.contains('yushu') ||
          id.contains('yu-shu') ||
          id.contains('meijia') ||
          id.contains('mei-jia') ||
          id.contains('sinji') ||
          id.contains('sin-ji') ||
          name.contains('女') ||
          name.contains('声音 2') ||
          name.contains('voice 2');
    }

    bool isSiri(Map<String, dynamic> v) {
      final name = (v['name'] as String? ?? '').toLowerCase();
      final id = (v['identifier'] as String? ?? '').toLowerCase();
      return name.contains('siri') || id.contains('siri');
    }

    bool isEn(Map<String, dynamic> v) {
      final lang = (v['language'] as String? ?? '').toLowerCase();
      return lang.startsWith('en');
    }

    int getQuality(Map<String, dynamic> v) {
      return v['quality'] as int? ?? 1;
    }

    // Sort voices:
    // 1. Siri Voice 4 (American accent) - Absolute top priority
    // 2. Other English Siri voices
    // 3. High quality Chinese Siri female voices
    // 4. Any other Siri voices
    // 5. Premium / Enhanced voices
    // 6. Chinese female voices
    // 7. Alphabetical
    voices.sort((a, b) {
      final aIs4 = isSiriVoice4(a);
      final bIs4 = isSiriVoice4(b);
      if (aIs4 != bIs4) return aIs4 ? -1 : 1;

      final aIsEnSiri = isSiri(a) && isEn(a);
      final bIsEnSiri = isSiri(b) && isEn(b);
      if (aIsEnSiri != bIsEnSiri) return aIsEnSiri ? -1 : 1;

      final aIsSiriFemale = isSiri(a) && isFemale(a);
      final bIsSiriFemale = isSiri(b) && isFemale(b);
      if (aIsSiriFemale != bIsSiriFemale) return aIsSiriFemale ? -1 : 1;

      final aIsSiri = isSiri(a);
      final bIsSiri = isSiri(b);
      if (aIsSiri != bIsSiri) return aIsSiri ? -1 : 1;

      final aQual = getQuality(a);
      final bQual = getQuality(b);
      if (aQual != bQual) return bQual.compareTo(aQual);

      final aIsFemale = isFemale(a);
      final bIsFemale = isFemale(b);
      if (aIsFemale != bIsFemale) return aIsFemale ? -1 : 1;

      return (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? '');
    });

    String? targetId = state.selectedVoiceId;
    String? targetName = state.selectedVoiceName;

    if (voices.isNotEmpty) {
      final siri4Match = voices.where((v) => isSiriVoice4(v)).firstOrNull;
      if (siri4Match != null && (targetId == null || !voices.any((v) => v['identifier'] == targetId))) {
        targetId = siri4Match['identifier'] as String?;
        targetName = siri4Match['name'] as String?;
      } else if (targetId == null) {
        final best = voices.first;
        targetId = best['identifier'] as String?;
        targetName = best['name'] as String?;
      }
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
