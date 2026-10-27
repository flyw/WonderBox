import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/storage/preferences_provider.dart';
import '../../../../core/storage/storage_keys.dart';
import '../../../voice/data/services/qwen3_tts_model_manager.dart';
import '../../../voice/data/services/qwen3_tts_service.dart';
import '../../data/services/tts_service.dart';

class TtsState {
  final bool isSpeaking;
  final String? currentSpeakingMessageId;
  final bool isAutoSpeakEnabled;
  final TtsEngine engine;
  final String qwen3Voice;
  final bool isQwen3Downloaded;
  final double qwen3DownloadProgress;
  final String? qwen3DownloadStatus;
  final String? selectedVoiceId;
  final String? selectedVoiceName;
  final double rate;
  final double pitch;
  final List<Map<String, dynamic>> availableVoices;
  final String? customEndpoint;
  final bool? isServerConnected;
  final String? lastErrorMessage;

  const TtsState({
    this.isSpeaking = false,
    this.currentSpeakingMessageId,
    this.isAutoSpeakEnabled = true,
    this.engine = TtsEngine.qwen3Tts,
    this.qwen3Voice = 'vivian',
    this.isQwen3Downloaded = false,
    this.qwen3DownloadProgress = 0.0,
    this.qwen3DownloadStatus,
    this.selectedVoiceId,
    this.selectedVoiceName,
    this.rate = 0.5,
    this.pitch = 1.0,
    this.availableVoices = const [],
    this.customEndpoint,
    this.isServerConnected,
    this.lastErrorMessage,
  });

  TtsState copyWith({
    bool? isSpeaking,
    String? currentSpeakingMessageId,
    bool? isAutoSpeakEnabled,
    TtsEngine? engine,
    String? qwen3Voice,
    bool? isQwen3Downloaded,
    double? qwen3DownloadProgress,
    String? qwen3DownloadStatus,
    String? selectedVoiceId,
    String? selectedVoiceName,
    double? rate,
    double? pitch,
    List<Map<String, dynamic>>? availableVoices,
    String? customEndpoint,
    bool? isServerConnected,
    String? lastErrorMessage,
  }) {
    return TtsState(
      isSpeaking: isSpeaking ?? this.isSpeaking,
      currentSpeakingMessageId: currentSpeakingMessageId,
      isAutoSpeakEnabled: isAutoSpeakEnabled ?? this.isAutoSpeakEnabled,
      engine: engine ?? this.engine,
      qwen3Voice: qwen3Voice ?? this.qwen3Voice,
      isQwen3Downloaded: isQwen3Downloaded ?? this.isQwen3Downloaded,
      qwen3DownloadProgress: qwen3DownloadProgress ?? this.qwen3DownloadProgress,
      qwen3DownloadStatus: qwen3DownloadStatus ?? this.qwen3DownloadStatus,
      selectedVoiceId: selectedVoiceId ?? this.selectedVoiceId,
      selectedVoiceName: selectedVoiceName ?? this.selectedVoiceName,
      rate: rate ?? this.rate,
      pitch: pitch ?? this.pitch,
      availableVoices: availableVoices ?? this.availableVoices,
      customEndpoint: customEndpoint ?? this.customEndpoint,
      isServerConnected: isServerConnected ?? this.isServerConnected,
      lastErrorMessage: lastErrorMessage ?? this.lastErrorMessage,
    );
  }
}

class TtsNotifier extends Notifier<TtsState> {
  late final TtsService _service;
  late final SharedPreferences _prefs;

  @override
  TtsState build() {
    _service = ref.watch(ttsServiceProvider);
    _prefs = ref.watch(sharedPreferencesProvider);
    _service.onSpeakingChanged = (speaking) {
      state = state.copyWith(
        isSpeaking: speaking,
        currentSpeakingMessageId: speaking ? state.currentSpeakingMessageId : null,
      );
    };

    final savedEngineName = _prefs.getString(StorageKeys.ttsEngine);
    final engine = savedEngineName == TtsEngine.systemApple.name
        ? TtsEngine.systemApple
        : TtsEngine.qwen3Tts; // Default to Qwen3-TTS
    final savedQwen3Voice = _prefs.getString(StorageKeys.qwen3Voice) ?? 'vivian';
    final savedVoiceId = _prefs.getString(StorageKeys.ttsVoiceId);
    final savedVoiceName = _prefs.getString(StorageKeys.ttsVoiceName);
    final savedRate = _prefs.getDouble(StorageKeys.ttsRate) ?? 0.5;
    final savedPitch = _prefs.getDouble(StorageKeys.ttsPitch) ?? 1.0;
    final savedAutoSpeak = _prefs.getBool(StorageKeys.ttsAutoSpeak) ?? true;
    final savedCustomEndpoint = _prefs.getString(StorageKeys.qwen3CustomEndpoint);

    // Check Qwen3 model & load available iOS voices asynchronously
    Future.microtask(() {
      if (ref.mounted) {
        checkQwen3ModelStatus();
        loadAvailableVoices();
        testServerConnection(savedCustomEndpoint);
      }
    });

    return TtsState(
      engine: engine,
      qwen3Voice: savedQwen3Voice,
      selectedVoiceId: savedVoiceId,
      selectedVoiceName: savedVoiceName,
      rate: savedRate,
      pitch: savedPitch,
      isAutoSpeakEnabled: savedAutoSpeak,
      customEndpoint: savedCustomEndpoint,
    );
  }

  Future<void> checkQwen3ModelStatus() async {
    try {
      final downloaded = await ref.read(qwen3TtsModelManagerProvider).isModelDownloaded();
      if (!ref.mounted) return;
      state = state.copyWith(isQwen3Downloaded: downloaded);
    } catch (_) {}
  }

  Future<void> downloadQwen3Model() async {
    final manager = ref.read(qwen3TtsModelManagerProvider);
    state = state.copyWith(
      qwen3DownloadProgress: 0.01,
      qwen3DownloadStatus: '正在准备下载 Qwen3-TTS 0.6B Q4...',
    );

    try {
      await manager.downloadModel(
        onProgress: (progress, status) {
          if (!ref.mounted) return;
          state = state.copyWith(
            qwen3DownloadProgress: progress,
            qwen3DownloadStatus: status,
            isQwen3Downloaded: progress >= 1.0,
          );
        },
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        qwen3DownloadStatus: '下载中断，请点击重试',
      );
    }
  }

  void setEngine(TtsEngine engine) {
    _prefs.setString(StorageKeys.ttsEngine, engine.name);
    state = state.copyWith(engine: engine);
  }

  void setQwen3Voice(String voice) {
    _prefs.setString(StorageKeys.qwen3Voice, voice);
    state = state.copyWith(qwen3Voice: voice);
  }

  void setCustomEndpoint(String endpoint) {
    final trimmed = endpoint.trim();
    if (trimmed.isEmpty) {
      _prefs.remove(StorageKeys.qwen3CustomEndpoint);
      state = state.copyWith(customEndpoint: null);
    } else {
      _prefs.setString(StorageKeys.qwen3CustomEndpoint, trimmed);
      state = state.copyWith(customEndpoint: trimmed);
    }
    testServerConnection(trimmed);
  }

  Future<void> testServerConnection([String? endpoint]) async {
    final target = endpoint ?? state.customEndpoint ?? 'http://127.0.0.1:58588/health';
    try {
      final qwen3Service = ref.read(qwen3TtsServiceProvider);
      final res = await qwen3Service.testConnection(target);
      if (!ref.mounted) return;
      state = state.copyWith(
        isServerConnected: res.ok,
        lastErrorMessage: res.ok ? null : res.message,
      );
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(isServerConnected: false);
    }
  }

  Future<void> loadAvailableVoices() async {
    final rawVoices = await _service.getAvailableVoices();
    if (!ref.mounted) return;

    // Filter strictly for US English (en-US) and CN Chinese (zh-CN)
    final voices = rawVoices.where((v) {
      final lang = (v['language'] as String? ?? '').toLowerCase().replaceAll('_', '-');
      return lang == 'en-us' || lang.startsWith('en-us') || lang == 'zh-cn' || lang.startsWith('zh-cn');
    }).toList();

    bool isSiriVoice4(Map<String, dynamic> v) {
      final name = (v['name'] as String? ?? '').toLowerCase();
      final id = (v['identifier'] as String? ?? '').toLowerCase();
      final lang = (v['language'] as String? ?? '').toLowerCase().replaceAll('_', '-');
      final isEn = lang == 'en-us' || lang.startsWith('en-us');
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
      final lang = (v['language'] as String? ?? '').toLowerCase().replaceAll('_', '-');
      return lang == 'en-us' || lang.startsWith('en-us');
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
      final hasMatchingVoice = targetId != null && voices.any((v) => v['identifier'] == targetId);

      if (!hasMatchingVoice) {
        if (siri4Match != null) {
          targetId = siri4Match['identifier'] as String?;
          targetName = siri4Match['name'] as String?;
        } else {
          final best = voices.first;
          targetId = best['identifier'] as String?;
          targetName = best['name'] as String?;
        }
        if (targetId != null) {
          _prefs.setString(StorageKeys.ttsVoiceId, targetId);
          if (targetName != null) {
            _prefs.setString(StorageKeys.ttsVoiceName, targetName);
          }
        }
      } else {
        final matchedVoice = voices.firstWhere((v) => v['identifier'] == targetId);
        targetName = matchedVoice['name'] as String? ?? targetName;
      }
    }

    state = state.copyWith(
      availableVoices: voices,
      selectedVoiceId: targetId,
      selectedVoiceName: targetName,
    );
  }

  void selectVoice(String voiceId, String name) {
    _prefs.setString(StorageKeys.ttsVoiceId, voiceId);
    _prefs.setString(StorageKeys.ttsVoiceName, name);
    state = state.copyWith(
      selectedVoiceId: voiceId,
      selectedVoiceName: name,
    );
  }

  void setRate(double rate) {
    _prefs.setDouble(StorageKeys.ttsRate, rate);
    state = state.copyWith(rate: rate);
  }

  void setPitch(double pitch) {
    _prefs.setDouble(StorageKeys.ttsPitch, pitch);
    state = state.copyWith(pitch: pitch);
  }

  void toggleAutoSpeak() {
    final next = !state.isAutoSpeakEnabled;
    _prefs.setBool(StorageKeys.ttsAutoSpeak, next);
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
    state = state.copyWith(isSpeaking: true, currentSpeakingMessageId: messageId, lastErrorMessage: null);
    await _service.speak(
      text,
      engine: state.engine,
      qwen3Voice: state.qwen3Voice,
      rate: state.rate,
      pitch: state.pitch,
      voiceIdentifier: state.selectedVoiceId,
      customBaseUrl: state.customEndpoint,
      onError: (err) {
        state = state.copyWith(lastErrorMessage: err);
      },
    );
  }

  Future<void> autoSpeak(String text) async {
    if (!state.isAutoSpeakEnabled) return;
    state = state.copyWith(isSpeaking: true, lastErrorMessage: null);
    await _service.speak(
      text,
      engine: state.engine,
      qwen3Voice: state.qwen3Voice,
      rate: state.rate,
      pitch: state.pitch,
      voiceIdentifier: state.selectedVoiceId,
      customBaseUrl: state.customEndpoint,
      onError: (err) {
        state = state.copyWith(lastErrorMessage: err);
      },
    );
  }

  Future<void> stop() async {
    await _service.stop();
    state = state.copyWith(isSpeaking: false, currentSpeakingMessageId: null);
  }
}

final ttsControllerProvider = NotifierProvider<TtsNotifier, TtsState>(TtsNotifier.new);
