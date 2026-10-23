import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import '../services/qwen3_model_manager.dart';

final qwen3ModelManagerProvider = Provider<Qwen3ModelManager>((ref) {
  return Qwen3ModelManager();
});

final qwen3AsrServiceProvider = Provider<Qwen3AsrService>((ref) {
  final modelManager = ref.watch(qwen3ModelManagerProvider);
  return Qwen3AsrService(modelManager);
});

class Qwen3AsrService {
  final Qwen3ModelManager _modelManager;
  sherpa_onnx.OfflineRecognizer? _recognizer;
  bool _isBindingsInitialized = false;

  Qwen3AsrService(this._modelManager);

  Future<void> ensureInitialized() async {
    if (_recognizer != null) return;

    if (!_isBindingsInitialized) {
      sherpa_onnx.initBindings();
      _isBindingsInitialized = true;
    }

    final dir = await _modelManager.getModelDir();
    final convFrontendPath = '${dir.path}/conv_frontend.onnx';
    final encoderPath = '${dir.path}/encoder.int8.onnx';
    final decoderPath = '${dir.path}/decoder.int8.onnx';
    final tokenizerPath = '${dir.path}/tokenizer';

    final isDownloaded = await _modelManager.isModelDownloaded();
    if (!isDownloaded) {
      throw Exception('Qwen3-ASR 模型尚未下载完成');
    }

    final config = sherpa_onnx.OfflineRecognizerConfig(
      feat: const sherpa_onnx.FeatureConfig(
        sampleRate: 16000,
        featureDim: 80,
      ),
      model: sherpa_onnx.OfflineModelConfig(
        qwen3Asr: sherpa_onnx.OfflineQwen3AsrModelConfig(
          convFrontend: convFrontendPath,
          encoder: encoderPath,
          decoder: decoderPath,
          tokenizer: tokenizerPath,
          maxTotalLen: 512,
          maxNewTokens: 128,
        ),
        tokens: '',
        numThreads: 2,
        debug: false,
      ),
    );

    _recognizer = sherpa_onnx.OfflineRecognizer(config);
  }

  Future<String> transcribe(String wavFilePath) async {
    await ensureInitialized();

    final file = File(wavFilePath);
    if (!await file.exists()) {
      throw Exception('音频文件不存在: $wavFilePath');
    }

    final wave = sherpa_onnx.readWave(wavFilePath);
    if (wave.samples.isEmpty) {
      throw Exception('无法解析音频波形数据');
    }

    final recognizer = _recognizer!;
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
      recognizer.decode(stream);
      final result = recognizer.getResult(stream);
      final text = result.text.trim();
      return text;
    } finally {
      stream.free();
    }
  }

  void dispose() {
    _recognizer?.free();
    _recognizer = null;
  }
}
