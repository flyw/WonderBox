import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import '../services/ten_vad_model_manager.dart';
import 'streaming_paraformer_service.dart';

final tenVadModelManagerProvider = Provider<TenVadModelManager>((ref) {
  return TenVadModelManager();
});

final ambientVoiceServiceProvider = Provider<AmbientVoiceService>((ref) {
  final vadManager = ref.watch(tenVadModelManagerProvider);
  final paraformerService = ref.watch(streamingParaformerServiceProvider);
  return AmbientVoiceService(vadManager, paraformerService);
});

class AmbientVoiceService {
  final TenVadModelManager _vadManager;
  final StreamingParaformerService _paraformerService;
  final AudioRecorder _audioRecorder = AudioRecorder();

  // Configurable thresholds for distance, acoustic energy, and sensitivity
  double vadThreshold;
  double minSpeechDuration;
  double minSilenceDuration;
  double minRmsThreshold;

  sherpa_onnx.VoiceActivityDetector? _vad;
  sherpa_onnx.OnlineStream? _activeStream;
  StreamSubscription<Uint8List>? _recordStreamSub;
  bool _isListening = false;
  bool _isMuted = false;
  bool _lastDetectedState = false;
  String _currentLiveText = '';

  AmbientVoiceService(
    this._vadManager,
    this._paraformerService, {
    this.vadThreshold = 0.40,
    this.minSpeechDuration = 0.18,
    this.minSilenceDuration = 0.55,
    this.minRmsThreshold = 0.008,
  });

  bool get isListening => _isListening;
  bool get isMuted => _isMuted;

  void updateConfig({
    double? vadThreshold,
    double? minRmsThreshold,
    double? minSpeechDuration,
    double? minSilenceDuration,
  }) {
    bool needVadRebuild = false;
    if (vadThreshold != null && vadThreshold != this.vadThreshold) {
      this.vadThreshold = vadThreshold;
      needVadRebuild = true;
    }
    if (minSpeechDuration != null && minSpeechDuration != this.minSpeechDuration) {
      this.minSpeechDuration = minSpeechDuration;
      needVadRebuild = true;
    }
    if (minSilenceDuration != null && minSilenceDuration != this.minSilenceDuration) {
      this.minSilenceDuration = minSilenceDuration;
      needVadRebuild = true;
    }
    if (minRmsThreshold != null) {
      this.minRmsThreshold = minRmsThreshold;
    }
    if (needVadRebuild && _isListening) {
      _reconfigureVad();
    }
  }

  Future<void> _reconfigureVad() async {
    if (_vad == null) return;
    try {
      final vadModelPath = await _vadManager.getModelPath();
      final vadConfig = sherpa_onnx.VadModelConfig(
        tenVad: sherpa_onnx.TenVadModelConfig(
          model: vadModelPath,
          threshold: vadThreshold,
          minSilenceDuration: minSilenceDuration,
          minSpeechDuration: minSpeechDuration,
          windowSize: 256,
          maxSpeechDuration: 30.0,
        ),
        sampleRate: 16000,
        debug: false,
      );
      _vad?.free();
      _vad = sherpa_onnx.VoiceActivityDetector(
        config: vadConfig,
        bufferSizeInSeconds: 30,
      );
      debugPrint('[AmbientVoiceService] VAD reconfigured: threshold=$vadThreshold, minSpeech=$minSpeechDuration, minRms=$minRmsThreshold');
    } catch (e) {
      debugPrint('[AmbientVoiceService] Error reconfiguring VAD: $e');
    }
  }

  void setMuted(bool muted) {
    if (_isMuted == muted) return;
    _isMuted = muted;
    if (muted) {
      debugPrint('[AmbientVoiceService] Muted: assistant is active/speaking, dropping mic chunks');
      _activeStream?.free();
      _activeStream = null;
      _currentLiveText = '';
      _lastDetectedState = false;
      _vad?.clear();
      _vad?.reset();
    } else {
      debugPrint('[AmbientVoiceService] Unmuted: assistant stopped speaking, listening resumed');
      _lastDetectedState = false;
      _vad?.reset();
    }
  }

  Future<void> ensureInitialized() async {
    if (!await _vadManager.isModelDownloaded()) {
      await _vadManager.downloadModel();
    }
    await _paraformerService.ensureInitialized();
  }

  Future<bool> startListening({
    required void Function(String phrase) onPhraseTranscribed,
    void Function(String liveText)? onLiveText,
    void Function(bool isSpeechDetected)? onSpeechDetectedChanged,
    void Function(double currentRms, bool isEnergySufficient)? onRmsChanged,
    void Function(String error)? onError,
  }) async {
    if (_isListening) return true;

    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      onError?.call('缺少麦克风权限，无法开启伴听模式');
      return false;
    }

    try {
      await ensureInitialized();

      final vadModelPath = await _vadManager.getModelPath();

      sherpa_onnx.initBindings();

      final vadConfig = sherpa_onnx.VadModelConfig(
        tenVad: sherpa_onnx.TenVadModelConfig(
          model: vadModelPath,
          threshold: vadThreshold,
          minSilenceDuration: minSilenceDuration,
          minSpeechDuration: minSpeechDuration,
          windowSize: 256,
          maxSpeechDuration: 30.0,
        ),
        sampleRate: 16000,
        debug: false,
      );

      _vad?.free();
      _vad = sherpa_onnx.VoiceActivityDetector(
        config: vadConfig,
        bufferSizeInSeconds: 30,
      );

      _activeStream?.free();
      _activeStream = null;
      _currentLiveText = '';

      final recordStream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      _isListening = true;
      _lastDetectedState = false;

      // Residual buffer to ensure exact 256-sample window feeding
      var residualSamples = Float32List(0);
      const windowSize = 256;

      // Rolling pre-speech buffer (~400ms) to ensure speech onset is never lost
      final preSpeechBuffer = <Uint8List>[];
      const maxPreSpeechChunks = 4;

      _recordStreamSub?.cancel();
      _recordStreamSub = recordStream.listen(
        (Uint8List chunk) {
          if (_vad == null || !_isListening || _isMuted) return;

          final newSamples = _pcm16ToFloat32(chunk);
          final currentRms = _computeRms(newSamples);

          // Buffer incoming chunks before speech onset so leading syllables are preserved
          if (_activeStream == null) {
            preSpeechBuffer.add(chunk);
            if (preSpeechBuffer.length > maxPreSpeechChunks) {
              preSpeechBuffer.removeAt(0);
            }
          }

          // Check if acoustic energy meets the near-field physical volume threshold
          final isEnergySufficient = currentRms >= minRmsThreshold;
          onRmsChanged?.call(currentRms, isEnergySufficient);

          final totalLength = residualSamples.length + newSamples.length;
          final combined = Float32List(totalLength);
          combined.setAll(0, residualSamples);
          combined.setAll(residualSamples.length, newSamples);

          var offset = 0;
          while (offset + windowSize <= combined.length) {
            final slice = combined.sublist(offset, offset + windowSize);

            // If speech is already ongoing (_activeStream != null), maintain continuous audio flow.
            // If idle and acoustic energy is below the near-field threshold (distant sound / background noise),
            // feed digital silence to TEN VAD so distant speech does not trigger false activation.
            if (_activeStream != null || isEnergySufficient) {
              _vad!.acceptWaveform(slice);
            } else {
              _vad!.acceptWaveform(Float32List(windowSize));
            }
            offset += windowSize;
          }

          if (offset < combined.length) {
            residualSamples = combined.sublist(offset);
          } else {
            residualSamples = Float32List(0);
          }

          final detected = _vad!.isDetected();
          if (detected != _lastDetectedState) {
            _lastDetectedState = detected;
            onSpeechDetectedChanged?.call(detected);
            if (detected) {
              debugPrint('[AmbientVoiceService] Speech onset detected! RMS: ${currentRms.toStringAsFixed(4)} (gate: $minRmsThreshold), VAD threshold: $vadThreshold, minSpeech: $minSpeechDuration');
            }
          }

          if (detected && _activeStream == null) {
            // Speech started: initialize stream and immediately feed all pre-speech chunks
            _activeStream = _paraformerService.createStream();
            _currentLiveText = '';

            for (final preChunk in preSpeechBuffer) {
              final preHypothesis = _paraformerService.processChunk(_activeStream!, preChunk);
              if (preHypothesis.isNotEmpty) {
                _currentLiveText = preHypothesis;
                onLiveText?.call(_currentLiveText);
              }
            }
            preSpeechBuffer.clear();
          }

          // If active stream is recording speech, feed chunk for live typewriter feedback
          if (_activeStream != null) {
            final liveHypothesis = _paraformerService.processChunk(_activeStream!, chunk);
            if (liveHypothesis.isNotEmpty && liveHypothesis != _currentLiveText) {
              _currentLiveText = liveHypothesis;
              onLiveText?.call(_currentLiveText);
            }
          }

          while (!_vad!.isEmpty()) {
            final segment = _vad!.front();
            _vad!.pop();

            String finalPhrase = '';
            // Primary: transcribe the complete, pristine segment buffered by TEN VAD (onset to offset)
            if (segment.samples.isNotEmpty) {
              finalPhrase = _paraformerService.transcribeSamples(segment.samples).trim();
            }

            // Fallback: if segment transcription was empty, try finalizing active stream
            if (finalPhrase.isEmpty && _activeStream != null) {
              finalPhrase = _paraformerService.finalizeStream(_activeStream!).trim();
            }

            _activeStream?.free();
            _activeStream = null;
            _currentLiveText = '';
            preSpeechBuffer.clear();

            if (finalPhrase.isNotEmpty) {
              onPhraseTranscribed(finalPhrase);
            }
          }
        },
        onError: (e) {
          onError?.call('音频流录音异常: $e');
        },
      );

      return true;
    } catch (e) {
      _isListening = false;
      onError?.call('启动 TEN VAD 伴听服务失败: $e');
      return false;
    }
  }

  Future<void> stopListening() async {
    _isListening = false;
    _lastDetectedState = false;
    _activeStream?.free();
    _activeStream = null;
    _currentLiveText = '';

    await _recordStreamSub?.cancel();
    _recordStreamSub = null;
    try {
      await _audioRecorder.stop();
    } catch (_) {}

    _vad?.free();
    _vad = null;
  }

  Float32List _pcm16ToFloat32(Uint8List bytes) {
    final byteData = ByteData.sublistView(bytes);
    final numSamples = bytes.length ~/ 2;
    final samples = Float32List(numSamples);
    for (var i = 0; i < numSamples; i++) {
      final int16 = byteData.getInt16(i * 2, Endian.little);
      samples[i] = int16 / 32768.0;
    }
    return samples;
  }

  double _computeRms(Float32List samples) {
    if (samples.isEmpty) return 0.0;
    var sum = 0.0;
    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      sum += s * s;
    }
    return math.sqrt(sum / samples.length);
  }

  void dispose() {
    stopListening();
    _audioRecorder.dispose();
  }
}
