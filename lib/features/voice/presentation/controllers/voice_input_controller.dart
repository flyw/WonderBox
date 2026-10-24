import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import '../../data/datasources/streaming_paraformer_service.dart';

enum VoiceInputStatus {
  uninitialized,
  modelMissing,
  downloading,
  ready,
  recording,
  transcribing,
  error,
}

class VoiceInputState {
  final VoiceInputStatus status;
  final double downloadProgress;
  final String statusMessage;
  final String? lastRecognizedText;
  final String liveText;
  final String? errorMessage;
  final int recordingSeconds;

  const VoiceInputState({
    this.status = VoiceInputStatus.uninitialized,
    this.downloadProgress = 0.0,
    this.statusMessage = '',
    this.lastRecognizedText,
    this.liveText = '',
    this.errorMessage,
    this.recordingSeconds = 0,
  });

  VoiceInputState copyWith({
    VoiceInputStatus? status,
    double? downloadProgress,
    String? statusMessage,
    String? lastRecognizedText,
    String? liveText,
    String? errorMessage,
    int? recordingSeconds,
  }) {
    return VoiceInputState(
      status: status ?? this.status,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      statusMessage: statusMessage ?? this.statusMessage,
      lastRecognizedText: lastRecognizedText ?? this.lastRecognizedText,
      liveText: liveText ?? this.liveText,
      errorMessage: errorMessage ?? this.errorMessage,
      recordingSeconds: recordingSeconds ?? this.recordingSeconds,
    );
  }
}

class VoiceInputController extends Notifier<VoiceInputState> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  Timer? _timer;
  CancelToken? _downloadCancelToken;

  sherpa_onnx.OnlineStream? _onlineStream;
  StreamSubscription<Uint8List>? _recordStreamSub;
  String _confirmedText = '';
  String _currentClauseText = '';
  void Function(String text)? _onLiveTextCallback;

  @override
  VoiceInputState build() {
    ref.onDispose(() {
      _cleanupResources();
    });

    Future.microtask(() => checkModelStatus());
    return const VoiceInputState();
  }

  void _cleanupResources() {
    _timer?.cancel();
    _recordStreamSub?.cancel();
    _audioRecorder.dispose();
    _downloadCancelToken?.cancel();
    _onlineStream?.free();
    _onlineStream = null;
  }

  Future<void> checkModelStatus() async {
    final modelManager = ref.read(streamingModelManagerProvider);
    final isDownloaded = await modelManager.isModelDownloaded();
    state = state.copyWith(
      status: isDownloaded ? VoiceInputStatus.ready : VoiceInputStatus.modelMissing,
      statusMessage: isDownloaded ? '实时流式模型就绪' : '实时模型待下载',
    );
  }

  Future<void> downloadModel() async {
    final modelManager = ref.read(streamingModelManagerProvider);
    state = state.copyWith(
      status: VoiceInputStatus.downloading,
      downloadProgress: 0.0,
      statusMessage: '准备连接模型镜像...',
    );

    _downloadCancelToken = CancelToken();

    try {
      await modelManager.downloadModel(
        cancelToken: _downloadCancelToken,
        onProgress: (progress, statusText) {
          state = state.copyWith(
            downloadProgress: progress,
            statusMessage: statusText,
          );
        },
      );

      final service = ref.read(streamingParaformerServiceProvider);
      await service.ensureInitialized();

      state = state.copyWith(
        status: VoiceInputStatus.ready,
        statusMessage: 'Streaming-Paraformer 实时模型就绪',
      );
    } catch (e) {
      state = state.copyWith(
        status: VoiceInputStatus.error,
        errorMessage: '下载或初始化模型失败: $e',
        statusMessage: '下载出错',
      );
    } finally {
      _downloadCancelToken = null;
    }
  }

  Future<bool> startRecording({required void Function(String text) onLiveText}) async {
    if (state.status == VoiceInputStatus.modelMissing) {
      await downloadModel();
      if (state.status != VoiceInputStatus.ready) return false;
    }

    if (state.status == VoiceInputStatus.recording) return false;

    // Check microphone permission across platforms
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      state = state.copyWith(
        status: VoiceInputStatus.error,
        errorMessage: '需要麦克风权限以使用实时语音输入',
      );
      return false;
    }

    try {
      final service = ref.read(streamingParaformerServiceProvider);
      await service.ensureInitialized();

      _onlineStream?.free();
      _onlineStream = service.createStream();
      _confirmedText = '';
      _currentClauseText = '';
      _onLiveTextCallback = onLiveText;

      final recordStream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      _recordStreamSub?.cancel();
      _recordStreamSub = recordStream.listen((Uint8List chunk) {
        if (_onlineStream == null) return;

        final chunkText = service.processChunk(_onlineStream!, chunk);

        if (service.isEndpoint(_onlineStream!)) {
          if (chunkText.isNotEmpty) {
            _confirmedText += chunkText;
          }
          service.resetStream(_onlineStream!);
          _currentClauseText = '';
        } else {
          _currentClauseText = chunkText;
        }

        final fullText = '$_confirmedText$_currentClauseText'.trim();
        state = state.copyWith(liveText: fullText);
        _onLiveTextCallback?.call(fullText);
      });

      _timer?.cancel();
      var seconds = 0;
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        seconds++;
        state = state.copyWith(recordingSeconds: seconds);
      });

      state = state.copyWith(
        status: VoiceInputStatus.recording,
        recordingSeconds: 0,
        liveText: '',
        statusMessage: '正在聆听 (实时打字中)...',
        errorMessage: null,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        status: VoiceInputStatus.error,
        errorMessage: '启动实时录音失败: $e',
      );
      return false;
    }
  }

  Future<String> stopRecording() async {
    _timer?.cancel();
    await _recordStreamSub?.cancel();
    _recordStreamSub = null;
    await _audioRecorder.stop();

    if (_onlineStream != null) {
      final service = ref.read(streamingParaformerServiceProvider);
      final finalChunk = service.finalizeStream(_onlineStream!);
      if (finalChunk.isNotEmpty) {
        _currentClauseText = finalChunk;
      }
      _onlineStream?.free();
      _onlineStream = null;
    }

    final finalResult = '$_confirmedText$_currentClauseText'.trim();
    if (finalResult.isNotEmpty) {
      _onLiveTextCallback?.call(finalResult);
    }

    state = state.copyWith(
      status: VoiceInputStatus.ready,
      liveText: finalResult,
      lastRecognizedText: finalResult,
      statusMessage: '识别完成',
    );

    return finalResult;
  }

  Future<void> cancelRecording() async {
    _timer?.cancel();
    await _recordStreamSub?.cancel();
    _recordStreamSub = null;
    await _audioRecorder.stop();

    if (_onlineStream != null) {
      _onlineStream?.free();
      _onlineStream = null;
    }

    state = state.copyWith(
      status: VoiceInputStatus.ready,
      recordingSeconds: 0,
      liveText: '',
      statusMessage: '已取消录音',
    );
  }
}

final voiceInputControllerProvider =
    NotifierProvider<VoiceInputController, VoiceInputState>(
  VoiceInputController.new,
);
