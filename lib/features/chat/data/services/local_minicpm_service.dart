import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';
import '../../domain/models/llm_config.dart';
import 'minicpm_model_manager.dart';

final localMiniCpmServiceProvider = Provider<LocalMiniCpmService>((ref) {
  final dio = ref.watch(dioClientProvider);
  final modelManager = ref.watch(miniCpmModelManagerProvider);
  final service = LocalMiniCpmService(dio, modelManager);
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

class LocalMiniCpmService {
  final Dio _dio;
  final MiniCpmModelManager _modelManager;
  Process? _serverProcess;

  static const int port = 58588;
  static const String defaultLocalBaseUrl = 'http://127.0.0.1:58588/v1';
  static const String defaultModelName = 'MiniCPM-V-4.6';

  static const LlmConfig localConfig = LlmConfig(
    baseUrl: defaultLocalBaseUrl,
    model: defaultModelName,
    apiKey: 'local-minicpm',
    temperature: 0.7,
    systemPrompt: '你是一个专业的智能伴听分析助手，根据用户短句和会话上下文给出敏锐、精炼、结构清晰的分析回复。',
  );

  LocalMiniCpmService(this._dio, this._modelManager);

  /// Checks if the local llama-server is alive and ready
  Future<bool> isServerRunning() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(milliseconds: 500);
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/health'));
      final response = await request.close();
      final isOk = response.statusCode == 200;
      client.close();
      return isOk;
    } catch (_) {
      return false;
    }
  }

  /// Finds the llama-server binary in common locations or system PATH
  Future<String?> findLlamaServerBinary() async {
    final candidates = [
      '/opt/homebrew/bin/llama-server',
      '/usr/local/bin/llama-server',
      if (Platform.environment['HOME'] != null)
        '${Platform.environment['HOME']}/.local/bin/llama-server',
    ];

    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }

    try {
      final result = await Process.run('which', ['llama-server']);
      if (result.exitCode == 0) {
        final out = (result.stdout as String).trim();
        if (out.isNotEmpty && await File(out).exists()) return out;
      }
    } catch (_) {}

    return null;
  }

  /// Ensures llama-server is started with MiniCPM-V-4.6 GGUF
  Future<bool> startServerIfNeeded() async {
    if (await isServerRunning()) {
      return true;
    }

    final isDownloaded = await _modelManager.isModelDownloaded();
    if (!isDownloaded) {
      debugPrint('[LocalMiniCpmService] MiniCPM-V-4.6 model not downloaded yet');
      return false;
    }

    final binary = await findLlamaServerBinary();
    if (binary == null) {
      debugPrint('[LocalMiniCpmService] llama-server binary not found on this system');
      return false;
    }

    final modelPath = await _modelManager.getModelPath();
    debugPrint('[LocalMiniCpmService] Launching $binary with model $modelPath on port $port');

    try {
      _serverProcess = await Process.start(
        binary,
        [
          '-m',
          modelPath,
          '--port',
          '$port',
          '--host',
          '127.0.0.1',
          '-c',
          '2048',
          '--log-disable',
        ],
        mode: ProcessStartMode.normal,
      );

      _serverProcess?.exitCode.then((code) {
        debugPrint('[LocalMiniCpmService] llama-server process exited with code: $code');
        _serverProcess = null;
      });

      // Poll until ready (up to 8 seconds)
      for (var i = 0; i < 24; i++) {
        await Future.delayed(const Duration(milliseconds: 350));
        if (await isServerRunning()) {
          debugPrint('[LocalMiniCpmService] Local llama-server is ready and healthy!');
          return true;
        }
      }
    } catch (e) {
      debugPrint('[LocalMiniCpmService] Error starting llama-server: $e');
    }

    return await isServerRunning();
  }

  /// Disposes the service and stops the background server if it was spawned by this instance
  void dispose() {
    _serverProcess?.kill();
    _serverProcess = null;
  }
}
