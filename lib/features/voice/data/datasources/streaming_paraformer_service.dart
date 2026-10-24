import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import '../services/streaming_paraformer_model_manager.dart';

final streamingModelManagerProvider =
    Provider<StreamingParaformerModelManager>((ref) {
  return StreamingParaformerModelManager();
});

final streamingParaformerServiceProvider =
    Provider<StreamingParaformerService>((ref) {
  final modelManager = ref.watch(streamingModelManagerProvider);
  return StreamingParaformerService(modelManager);
});

class StreamingParaformerService {
  final StreamingParaformerModelManager _modelManager;
  sherpa_onnx.OnlineRecognizer? _recognizer;
  bool _isBindingsInitialized = false;

  StreamingParaformerService(this._modelManager);

  Future<void> ensureInitialized() async {
    if (_recognizer != null) return;

    if (!_isBindingsInitialized) {
      sherpa_onnx.initBindings();
      _isBindingsInitialized = true;
    }

    final dir = await _modelManager.getModelDir();
    final encoderPath = '${dir.path}/encoder.int8.onnx';
    final decoderPath = '${dir.path}/decoder.int8.onnx';
    final tokensPath = '${dir.path}/tokens.txt';

    final isDownloaded = await _modelManager.isModelDownloaded();
    if (!isDownloaded) {
      throw Exception('Streaming-Paraformer 实时模型尚未下载完成');
    }

    final config = sherpa_onnx.OnlineRecognizerConfig(
      feat: const sherpa_onnx.FeatureConfig(
        sampleRate: 16000,
        featureDim: 80,
      ),
      model: sherpa_onnx.OnlineModelConfig(
        paraformer: sherpa_onnx.OnlineParaformerModelConfig(
          encoder: encoderPath,
          decoder: decoderPath,
        ),
        tokens: tokensPath,
        numThreads: 2,
        debug: false,
      ),
      enableEndpoint: true,
      rule1MinTrailingSilence: 2.4,
      rule2MinTrailingSilence: 1.2,
      rule3MinUtteranceLength: 20,
    );

    _recognizer = sherpa_onnx.OnlineRecognizer(config);
  }

  sherpa_onnx.OnlineStream createStream() {
    if (_recognizer == null) {
      throw Exception('OnlineRecognizer 未初始化');
    }
    return _recognizer!.createStream();
  }

  /// Feeds raw 16-bit PCM bytes (16kHz mono) and returns current decoded hypothesis.
  String processChunk(sherpa_onnx.OnlineStream stream, Uint8List pcmBytes) {
    if (_recognizer == null) return '';

    final samples = _pcm16ToFloat32(pcmBytes);
    stream.acceptWaveform(samples: samples, sampleRate: 16000);

    while (_recognizer!.isReady(stream)) {
      _recognizer!.decode(stream);
    }

    final result = _recognizer!.getResult(stream);
    return result.text;
  }

  /// Signals end-of-audio, decodes any remaining buffered frames and returns final hypothesis.
  String finalizeStream(sherpa_onnx.OnlineStream stream) {
    if (_recognizer == null) return '';

    stream.inputFinished();
    while (_recognizer!.isReady(stream)) {
      _recognizer!.decode(stream);
    }

    final result = _recognizer!.getResult(stream);
    return result.text;
  }

  bool isEndpoint(sherpa_onnx.OnlineStream stream) {
    return _recognizer?.isEndpoint(stream) ?? false;
  }

  void resetStream(sherpa_onnx.OnlineStream stream) {
    _recognizer?.reset(stream);
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

  void dispose() {
    _recognizer?.free();
    _recognizer = null;
  }
}
