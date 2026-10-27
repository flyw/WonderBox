import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'qwen3_tts_model_manager.dart';

final qwen3TtsServiceProvider = Provider<Qwen3TtsService>((ref) {
  final modelManager = ref.watch(qwen3TtsModelManagerProvider);
  return Qwen3TtsService(modelManager);
});

class Qwen3VoiceProfile {
  final String id;
  final String name;
  final String description;
  final String gender;
  final String iconEmoji;

  const Qwen3VoiceProfile({
    required this.id,
    required this.name,
    required this.description,
    required this.gender,
    required this.iconEmoji,
  });
}

class Qwen3TtsService {
  final Qwen3TtsModelManager modelManager;

  static const List<Qwen3VoiceProfile> presetVoices = [
    Qwen3VoiceProfile(
      id: 'vivian',
      name: 'Vivian (灵动亲和)',
      description: '自然轻快、元气生动，伴听分析推荐',
      gender: 'female',
      iconEmoji: '🌸',
    ),
    Qwen3VoiceProfile(
      id: 'serena',
      name: 'Serena (温柔知性)',
      description: '温婉柔和、语调舒缓，长句朗读极佳',
      gender: 'female',
      iconEmoji: '🍃',
    ),
    Qwen3VoiceProfile(
      id: 'ryan',
      name: 'Ryan (活力阳光)',
      description: '清晰挺拔、朝气蓬勃青年男声',
      gender: 'male',
      iconEmoji: '🎙️',
    ),
    Qwen3VoiceProfile(
      id: 'uncle',
      name: 'Uncle (沉稳磁性)',
      description: '厚重从容、低沉专业叙事大叔音',
      gender: 'male',
      iconEmoji: '☕',
    ),
  ];

  static const int defaultPort = 58588;
  static const int speechCppPort = 58589;
  static const String defaultLocalBaseUrl = 'http://127.0.0.1:58588/v1/audio/speech';
  static const String speechCppBaseUrl = 'http://127.0.0.1:58589/v1/audio/speech';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 45),
      responseType: ResponseType.bytes,
    ),
  );

  Qwen3TtsService(this.modelManager);

  /// Checks if a local Qwen3-TTS inference endpoint is active
  Future<bool> isServiceAvailable() async {
    for (final url in [
      'http://127.0.0.1:$defaultPort/health',
      'http://127.0.0.1:$speechCppPort/health',
    ]) {
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(milliseconds: 1500);
        final req = await client.getUrl(Uri.parse(url));
        final resp = await req.close();
        client.close();
        if (resp.statusCode == 200) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Synthesizes text to a local WAV audio file using Qwen3-TTS 0.6B Q4
  Future<String?> synthesizeToWav(
    String text, {
    String voice = 'vivian',
    double speed = 1.0,
    String? customBaseUrl,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final endpoints = [
      if (customBaseUrl != null && customBaseUrl.isNotEmpty) customBaseUrl,
      defaultLocalBaseUrl,
      speechCppBaseUrl,
    ];

    final cacheDir = await getTemporaryDirectory();
    final outputFile = File('${cacheDir.path}/qwen3_tts_${DateTime.now().millisecondsSinceEpoch}.wav');

    final payload = {
      'model': 'qwen3-tts-0.6b-q4',
      'input': trimmed,
      'voice': voice,
      'response_format': 'wav',
      'speed': speed,
    };

    for (final endpoint in endpoints) {
      try {
        final response = await _dio.post<List<int>>(
          endpoint,
          data: payload,
          options: Options(
            headers: {'Content-Type': 'application/json'},
          ),
        );

        if (response.statusCode == 200 && response.data != null && response.data!.isNotEmpty) {
          await outputFile.writeAsBytes(response.data!);
          return outputFile.path;
        }
      } catch (e) {
        debugPrint('[Qwen3TtsService] Endpoint $endpoint error: $e');
      }
    }

    return null;
  }
}
