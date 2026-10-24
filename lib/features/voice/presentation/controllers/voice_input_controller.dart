import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../data/datasources/qwen3_asr_service.dart';

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
  final String? errorMessage;
  final int recordingSeconds;

  const VoiceInputState({
    this.status = VoiceInputStatus.uninitialized,
    this.downloadProgress = 0.0,
    this.statusMessage = '',
    this.lastRecognizedText,
    this.errorMessage,
    this.recordingSeconds = 0,
  });

  VoiceInputState copyWith({
    VoiceInputStatus? status,
    double? downloadProgress,
    String? statusMessage,
    String? lastRecognizedText,
    String? errorMessage,
    int? recordingSeconds,
  }) {
    return VoiceInputState(
      status: status ?? this.status,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      statusMessage: statusMessage ?? this.statusMessage,
      lastRecognizedText: lastRecognizedText ?? this.lastRecognizedText,
      errorMessage: errorMessage ?? this.errorMessage,
      recordingSeconds: recordingSeconds ?? this.recordingSeconds,
    );
  }
}

class VoiceInputController extends Notifier<VoiceInputState> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  Timer? _timer;
  String? _currentRecordingPath;
  CancelToken? _downloadCancelToken;

  @override
  VoiceInputState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _audioRecorder.dispose();
      _downloadCancelToken?.cancel();
    });

    Future.microtask(() => checkModelStatus());
    return const VoiceInputState();
  }

  Future<void> checkModelStatus() async {
    final modelManager = ref.read(qwen3ModelManagerProvider);
    final isDownloaded = await modelManager.isModelDownloaded();
    state = state.copyWith(
      status: isDownloaded ? VoiceInputStatus.ready : VoiceInputStatus.modelMissing,
      statusMessage: isDownloaded ? 'Qwen3 模型就绪' : 'Qwen3 模型待下载',
    );
  }

  Future<void> downloadModel() async {
    final modelManager = ref.read(qwen3ModelManagerProvider);
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

      final asrService = ref.read(qwen3AsrServiceProvider);
      await asrService.ensureInitialized();

      state = state.copyWith(
        status: VoiceInputStatus.ready,
        statusMessage: 'Qwen3-ASR 模型加载完成',
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

  Future<bool> startRecording() async {
    if (state.status == VoiceInputStatus.modelMissing) {
      await downloadModel();
      if (state.status != VoiceInputStatus.ready) return false;
    }

    if (state.status == VoiceInputStatus.recording) return false;

    // Check permission via AudioRecorder (cross-platform: macOS, iOS, Android)
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      state = state.copyWith(
        status: VoiceInputStatus.error,
        errorMessage: '需要麦克风权限以使用语音输入',
      );
      return false;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      _currentRecordingPath =
          '${tempDir.path}/record_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _currentRecordingPath!,
      );

      _timer?.cancel();
      var seconds = 0;
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        seconds++;
        state = state.copyWith(recordingSeconds: seconds);
      });

      state = state.copyWith(
        status: VoiceInputStatus.recording,
        recordingSeconds: 0,
        statusMessage: '正在聆听中...',
        errorMessage: null,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        status: VoiceInputStatus.error,
        errorMessage: '启动录音失败: $e',
      );
      return false;
    }
  }

  Future<String?> stopRecordingAndTranscribe() async {
    _timer?.cancel();
    if (state.status != VoiceInputStatus.recording) return null;

    state = state.copyWith(
      status: VoiceInputStatus.transcribing,
      statusMessage: 'Qwen3 本地识别中...',
    );

    try {
      final path = await _audioRecorder.stop();
      final wavPath = path ?? _currentRecordingPath;
      if (wavPath == null) throw Exception('录音路径无效');

      final asrService = ref.read(qwen3AsrServiceProvider);
      final text = await asrService.transcribe(wavPath);

      state = state.copyWith(
        status: VoiceInputStatus.ready,
        lastRecognizedText: text,
        statusMessage: '识别完成',
      );

      // Clean up temporary audio file
      final file = File(wavPath);
      if (await file.exists()) {
        await file.delete();
      }

      return text;
    } catch (e) {
      state = state.copyWith(
        status: VoiceInputStatus.error,
        errorMessage: '识别失败: $e',
        statusMessage: '识别出错',
      );
      return null;
    }
  }

  Future<void> cancelRecording() async {
    _timer?.cancel();
    await _audioRecorder.stop();
    if (_currentRecordingPath != null) {
      final file = File(_currentRecordingPath!);
      if (await file.exists()) {
        await file.delete();
      }
    }
    state = state.copyWith(
      status: VoiceInputStatus.ready,
      recordingSeconds: 0,
      statusMessage: '已取消录音',
    );
  }
}

final voiceInputControllerProvider =
    NotifierProvider<VoiceInputController, VoiceInputState>(
  VoiceInputController.new,
);
