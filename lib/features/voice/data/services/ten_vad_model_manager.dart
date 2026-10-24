import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class TenVadModelManager {
  static const String _modelFileName = 'ten-vad.onnx';

  static const List<String> _downloadMirrors = [
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/ten-vad.onnx',
    'https://hf-mirror.com/TigreGotico/ten-vad-onnx/resolve/main/ten-vad.onnx',
    'https://huggingface.co/TigreGotico/ten-vad-onnx/resolve/main/ten-vad.onnx',
  ];

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 2),
      headers: {
        'User-Agent': 'Mozilla/5.0 WonderBox-Mobile/1.0',
      },
    ),
  );

  Future<String> getModelDirectoryPath() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDocDir.path}/models/ten_vad');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    return modelDir.path;
  }

  Future<String> getModelPath() async {
    final dir = await getModelDirectoryPath();
    return '$dir/$_modelFileName';
  }

  Future<bool> isModelDownloaded() async {
    final path = await getModelPath();
    final file = File(path);
    if (!await file.exists()) return false;
    final length = await file.length();
    return length > 100 * 1024; // > 100KB is valid
  }

  Future<void> downloadModel({
    CancelToken? cancelToken,
    void Function(double progress, String statusText)? onProgress,
  }) async {
    final targetPath = await getModelPath();
    final targetFile = File(targetPath);
    if (await targetFile.exists() && await targetFile.length() > 100 * 1024) {
      onProgress?.call(1.0, 'TEN VAD 模型已存在');
      return;
    }

    final tempPath = '$targetPath.tmp';
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    Exception? lastException;

    for (final url in _downloadMirrors) {
      try {
        onProgress?.call(0.1, '正在下载 TEN VAD 模型 (${url.contains('github') ? 'GitHub' : 'Mirror'})...');

        await _dio.download(
          url,
          tempPath,
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              final progress = received / total;
              onProgress?.call(
                progress,
                '下载 TEN VAD: ${(received / 1024).toStringAsFixed(1)}KB / ${(total / 1024).toStringAsFixed(1)}KB',
              );
            }
          },
        );

        if (await tempFile.exists() && await tempFile.length() > 100 * 1024) {
          await tempFile.rename(targetPath);
          onProgress?.call(1.0, 'TEN VAD 模型准备就绪');
          return;
        }
      } catch (e) {
        lastException = Exception('Failed from $url: $e');
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    }

    throw lastException ?? Exception('无法从任何源下载 TEN VAD 模型');
  }
}
