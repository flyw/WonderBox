import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final qwen3TtsModelManagerProvider = Provider<Qwen3TtsModelManager>((ref) {
  return Qwen3TtsModelManager();
});

class Qwen3TtsModelManager {
  static const String modelFileName = 'qwen3-tts-0.6b-customvoice-q4_k_m.gguf';

  static const List<String> _mirrors = [
    'https://hf-mirror.com/BricksDisplay/Qwen3-TTS-12Hz-0.6B-CustomVoice-GGUF/resolve/main/qwen3-tts-0.6b-customvoice-q4_k_m.gguf',
    'https://huggingface.co/BricksDisplay/Qwen3-TTS-12Hz-0.6B-CustomVoice-GGUF/resolve/main/qwen3-tts-0.6b-customvoice-q4_k_m.gguf',
    'https://hf-mirror.com/mradermacher/Qwen3-TTS-12Hz-0.6B-Base-GGUF/resolve/main/Qwen3-TTS-12Hz-0.6B-Base.Q4_K_M.gguf',
    'https://huggingface.co/mradermacher/Qwen3-TTS-12Hz-0.6B-Base-GGUF/resolve/main/Qwen3-TTS-12Hz-0.6B-Base.Q4_K_M.gguf',
  ];

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 10),
      headers: {
        'User-Agent': 'Mozilla/5.0 WonderBox-Mobile/1.0',
      },
    ),
  );

  Future<Directory> getModelDir() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${appDir.path}/models/qwen3_tts_0.6b');
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }
      return modelDir;
    } catch (_) {
      final fallbackDir = Directory('${Directory.systemTemp.path}/models/qwen3_tts_0.6b');
      if (!await fallbackDir.exists()) {
        await fallbackDir.create(recursive: true);
      }
      return fallbackDir;
    }
  }

  Future<String> getModelPath() async {
    final dir = await getModelDir();
    return '${dir.path}/$modelFileName';
  }

  Future<bool> isModelDownloaded() async {
    final path = await getModelPath();
    final file = File(path);
    if (!await file.exists()) return false;
    final length = await file.length();
    // Q4_K_M is around 380MB ~ 450MB; accept if > 300MB
    return length > 300 * 1024 * 1024;
  }

  Future<int> getDownloadedSizeBytes() async {
    final path = await getModelPath();
    final file = File(path);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }

  Future<void> downloadModel({
    required void Function(double progress, String statusText) onProgress,
    CancelToken? cancelToken,
  }) async {
    final targetPath = await getModelPath();
    final targetFile = File(targetPath);
    if (await targetFile.exists() && await targetFile.length() > 300 * 1024 * 1024) {
      onProgress(1.0, 'Qwen3-TTS 0.6B Q4 模型已就绪');
      return;
    }

    final tempPath = '$targetPath.tmp';
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    Exception? lastException;
    bool downloaded = false;

    for (final url in _mirrors) {
      try {
        onProgress(0.01, '正在连接 Qwen3-TTS 镜像节点...');

        await _dio.download(
          url,
          tempPath,
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              final progress = (received / total).clamp(0.0, 1.0);
              final mbReceived = (received / 1024 / 1024).toStringAsFixed(1);
              final mbTotal = (total / 1024 / 1024).toStringAsFixed(1);
              onProgress(
                progress,
                '下载中: $mbReceived MB / $mbTotal MB (${(progress * 100).toStringAsFixed(0)}%)',
              );
            }
          },
        );

        final downloadedTemp = File(tempPath);
        if (await downloadedTemp.exists() && await downloadedTemp.length() > 300 * 1024 * 1024) {
          if (await targetFile.exists()) {
            await targetFile.delete();
          }
          await downloadedTemp.rename(targetPath);
          downloaded = true;
          onProgress(1.0, 'Qwen3-TTS 0.6B Q4 下载完成');
          break;
        }
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        onProgress(0.0, '节点切换重试中...');
      }
    }

    if (!downloaded) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      throw lastException ?? Exception('无法下载 Qwen3-TTS 0.6B Q4 模型文件');
    }
  }
}
