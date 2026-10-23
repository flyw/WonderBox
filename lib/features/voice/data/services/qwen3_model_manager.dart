import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class Qwen3ModelManager {
  static const String _hfBaseUrl =
      'https://hf-mirror.com/csukuangfj2/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25/resolve/main';

  final Dio _dio = Dio();

  Future<Directory> getModelDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDir.path}/models/qwen3_asr_0.6b');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    return modelDir;
  }

  Future<bool> isModelDownloaded() async {
    final dir = await getModelDir();
    final conv = File('${dir.path}/conv_frontend.onnx');
    final enc = File('${dir.path}/encoder.int8.onnx');
    final dec = File('${dir.path}/decoder.int8.onnx');
    final vocab = File('${dir.path}/tokenizer/vocab.json');

    return await conv.exists() &&
        await enc.exists() &&
        await dec.exists() &&
        await vocab.exists();
  }

  Future<void> downloadModel({
    required void Function(double progress, String statusText) onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await getModelDir();
    final tokenizerDir = Directory('${dir.path}/tokenizer');
    if (!await tokenizerDir.exists()) {
      await tokenizerDir.create(recursive: true);
    }

    final files = [
      {'remote': 'conv_frontend.onnx', 'local': '${dir.path}/conv_frontend.onnx', 'weight': 0.05},
      {'remote': 'encoder.int8.onnx', 'local': '${dir.path}/encoder.int8.onnx', 'weight': 0.25},
      {'remote': 'decoder.int8.onnx', 'local': '${dir.path}/decoder.int8.onnx', 'weight': 0.65},
      {'remote': 'tokenizer/vocab.json', 'local': '${dir.path}/tokenizer/vocab.json', 'weight': 0.02},
      {'remote': 'tokenizer/merges.txt', 'local': '${dir.path}/tokenizer/merges.txt', 'weight': 0.015},
      {'remote': 'tokenizer/tokenizer_config.json', 'local': '${dir.path}/tokenizer/tokenizer_config.json', 'weight': 0.015},
    ];

    double accumulatedProgress = 0.0;

    for (var i = 0; i < files.length; i++) {
      final item = files[i];
      final localFile = File(item['local'] as String);
      final remotePath = item['remote'] as String;
      final weight = item['weight'] as double;

      if (await localFile.exists() && (await localFile.length()) > 0) {
        accumulatedProgress += weight;
        continue;
      }

      final url = '$_hfBaseUrl/$remotePath';
      final fileName = remotePath.split('/').last;

      onProgress(accumulatedProgress, '正在下载 $fileName (${i + 1}/${files.length})...');

      await _dio.download(
        url,
        localFile.path,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final fileFraction = (received / total) * weight;
            final currentProgress = (accumulatedProgress + fileFraction).clamp(0.0, 1.0);
            final mbReceived = (received / 1024 / 1024).toStringAsFixed(1);
            final mbTotal = (total / 1024 / 1024).toStringAsFixed(1);
            onProgress(
              currentProgress,
              '下载 $fileName: $mbReceived MB / $mbTotal MB',
            );
          }
        },
      );

      accumulatedProgress += weight;
    }

    onProgress(1.0, 'Qwen3-ASR 模型就绪');
  }
}
