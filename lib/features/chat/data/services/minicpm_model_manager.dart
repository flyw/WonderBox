import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final miniCpmModelManagerProvider = Provider<MiniCpmModelManager>((ref) {
  return MiniCpmModelManager();
});

class MiniCpmModelManager {
  static const String modelFileName = 'MiniCPM-V-4_6-Q4_K_M.gguf';
  static const String mmprojFileName = 'mmproj-model-f16.gguf';

  static const List<String> _mirrors = [
    'https://hf-mirror.com/openbmb/MiniCPM-V-4.6-gguf/resolve/main/$modelFileName',
    'https://huggingface.co/openbmb/MiniCPM-V-4.6-gguf/resolve/main/$modelFileName',
  ];

  static const List<String> _mmprojMirrors = [
    'https://hf-mirror.com/openbmb/MiniCPM-V-4.6-gguf/resolve/main/$mmprojFileName',
    'https://huggingface.co/openbmb/MiniCPM-V-4.6-gguf/resolve/main/$mmprojFileName',
  ];

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 10),
      headers: {
        'User-Agent': 'Mozilla/5.0 WonderBox-Mobile/1.0',
      },
    ),
  );

  Future<String> getModelDirectoryPath() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDocDir.path}/models/minicpm_v');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    return modelDir.path;
  }

  Future<String> getModelPath() async {
    final dir = await getModelDirectoryPath();
    return '$dir/$modelFileName';
  }

  Future<String> getMmprojPath() async {
    final dir = await getModelDirectoryPath();
    return '$dir/$mmprojFileName';
  }

  Future<bool> isModelDownloaded() async {
    final path = await getModelPath();
    final file = File(path);
    if (!await file.exists()) return false;
    final length = await file.length();
    // 504 MB is ~529,101,504 bytes; accept if > 500 MB
    return length > 500 * 1024 * 1024;
  }

  Future<bool> isMmprojDownloaded() async {
    final path = await getMmprojPath();
    final file = File(path);
    if (!await file.exists()) return false;
    final length = await file.length();
    // mmproj is ~1,108,746,944 bytes (~1.05 GB); accept if > 1 GB
    return length > 1000 * 1024 * 1024;
  }

  Future<void> downloadModel({
    CancelToken? cancelToken,
    void Function(double progress, String statusText)? onProgress,
  }) async {
    final targetPath = await getModelPath();
    final targetFile = File(targetPath);
    if (await targetFile.exists() && await targetFile.length() > 500 * 1024 * 1024) {
      onProgress?.call(1.0, 'MiniCPM-V-4.6 本地模型已就绪');
      return;
    }

    final tempPath = '$targetPath.tmp';
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    Exception? lastException;

    for (final url in _mirrors) {
      try {
        onProgress?.call(0.01, '正在连接 MiniCPM-V-4.6 GGUF 镜像...');

        await _dio.download(
          url,
          tempPath,
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              final progress = received / total;
              final recMB = (received / (1024 * 1024)).toStringAsFixed(1);
              final totMB = (total / (1024 * 1024)).toStringAsFixed(1);
              onProgress?.call(
                progress,
                '下载 MiniCPM-V-4.6 (Q4_K_M): $recMB MB / $totMB MB (${(progress * 100).toStringAsFixed(0)}%)',
              );
            }
          },
        );

        if (await tempFile.exists() && await tempFile.length() > 500 * 1024 * 1024) {
          await tempFile.rename(targetPath);
          onProgress?.call(1.0, 'MiniCPM-V-4.6 模型下载完成');
          return;
        }
      } catch (e) {
        lastException = Exception('Failed to download from $url: $e');
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    }

    throw lastException ?? Exception('无法从任何镜像下载 MiniCPM-V-4.6 模型');
  }

  Future<void> downloadMmproj({
    CancelToken? cancelToken,
    void Function(double progress, String statusText)? onProgress,
  }) async {
    final targetPath = await getMmprojPath();
    final targetFile = File(targetPath);
    if (await targetFile.exists() && await targetFile.length() > 1000 * 1024 * 1024) {
      onProgress?.call(1.0, 'MiniCPM-V-4.6 视觉权重 (mmproj) 已就绪');
      return;
    }

    final tempPath = '$targetPath.tmp';
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    Exception? lastException;

    for (final url in _mmprojMirrors) {
      try {
        onProgress?.call(0.01, '正在连接 MiniCPM-V-4.6 视觉权重镜像...');

        await _dio.download(
          url,
          tempPath,
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              final progress = received / total;
              final recMB = (received / (1024 * 1024)).toStringAsFixed(1);
              final totMB = (total / (1024 * 1024)).toStringAsFixed(1);
              onProgress?.call(
                progress,
                '下载视觉权重 (mmproj): $recMB MB / $totMB MB (${(progress * 100).toStringAsFixed(0)}%)',
              );
            }
          },
        );

        if (await tempFile.exists() && await tempFile.length() > 1000 * 1024 * 1024) {
          await tempFile.rename(targetPath);
          onProgress?.call(1.0, 'MiniCPM-V-4.6 视觉权重下载完成');
          return;
        }
      } catch (e) {
        lastException = Exception('Failed to download mmproj from $url: $e');
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    }

    throw lastException ?? Exception('无法从任何镜像下载 MiniCPM-V-4.6 视觉权重');
  }
}
