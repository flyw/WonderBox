import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class StreamingParaformerModelManager {
  static const List<String> _baseUrls = [
    'https://hf-mirror.com/csukuangfj/sherpa-onnx-streaming-paraformer-bilingual-zh-en/resolve/main',
    'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-paraformer-bilingual-zh-en/resolve/main',
  ];

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 5),
    ),
  );

  Future<Directory> getModelDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDir.path}/models/streaming_paraformer');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    return modelDir;
  }

  Future<bool> isModelDownloaded() async {
    final dir = await getModelDir();
    final encoder = File('${dir.path}/encoder.int8.onnx');
    final decoder = File('${dir.path}/decoder.int8.onnx');
    final tokens = File('${dir.path}/tokens.txt');

    return await encoder.exists() &&
        await decoder.exists() &&
        await tokens.exists();
  }

  Future<void> downloadModel({
    required void Function(double progress, String statusText) onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await getModelDir();

    final files = [
      {'remote': 'tokens.txt', 'local': '${dir.path}/tokens.txt', 'weight': 0.05},
      {'remote': 'decoder.int8.onnx', 'local': '${dir.path}/decoder.int8.onnx', 'weight': 0.35},
      {'remote': 'encoder.int8.onnx', 'local': '${dir.path}/encoder.int8.onnx', 'weight': 0.60},
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

      final fileName = remotePath.split('/').last;
      onProgress(accumulatedProgress, '准备下载 $fileName (${i + 1}/${files.length})...');

      bool downloaded = false;
      Object? lastError;

      for (final baseUrl in _baseUrls) {
        final url = '$baseUrl/$remotePath';
        try {
          await _dio.download(
            url,
            localFile.path,
            cancelToken: cancelToken,
            onReceiveProgress: (received, total) {
              if (total > 0) {
                final fileFraction = (received / total) * weight;
                final currentProgress =
                    (accumulatedProgress + fileFraction).clamp(0.0, 1.0);
                final mbReceived = (received / 1024 / 1024).toStringAsFixed(1);
                final mbTotal = (total / 1024 / 1024).toStringAsFixed(1);
                onProgress(
                  currentProgress,
                  '下载 $fileName: $mbReceived MB / $mbTotal MB',
                );
              }
            },
          );
          downloaded = true;
          break;
        } catch (e) {
          lastError = e;
          if (cancelToken?.isCancelled ?? false) {
            rethrow;
          }
          if (await localFile.exists()) {
            await localFile.delete();
          }
        }
      }

      if (!downloaded) {
        throw Exception('下载 $fileName 失败: $lastError');
      }

      accumulatedProgress += weight;
    }

    onProgress(1.0, 'Streaming-Paraformer 实时模型就绪');
  }
}
