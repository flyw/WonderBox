import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final ttsServiceProvider = Provider<TtsService>((ref) {
  final service = TtsService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

class TtsService {
  static const _channel = MethodChannel('wonderbox/tts');
  void Function(bool isSpeaking)? onSpeakingChanged;

  TtsService() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onStart':
        onSpeakingChanged?.call(true);
        break;
      case 'onComplete':
      case 'onCancel':
        onSpeakingChanged?.call(false);
        break;
    }
  }

  /// Strips markdown symbols, thinking blocks, code fences, and URLs
  /// so TTS outputs smooth, natural spoken Chinese sentences.
  static String cleanMarkdown(String text) {
    var cleaned = text;

    // Remove internal reasoning/thinking tags (e.g. DeepSeek / R1 style)
    cleaned = cleaned.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
    cleaned = cleaned.replaceAll(RegExp(r'<reasoning>[\s\S]*?</reasoning>'), '');

    // Remove diagnostic tags like 【Jev-Style-0.8B ...】
    cleaned = cleaned.replaceAll(RegExp(r'【[^】]*】'), '');

    // Remove code blocks
    cleaned = cleaned.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    cleaned = cleaned.replaceAll(RegExp(r'`[^`]*`'), '');

    // Remove Markdown headers (#, ##, etc.)
    cleaned = cleaned.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');

    // Remove bold and italic markers (*, **, ***, _)
    cleaned = cleaned.replaceAll(RegExp(r'[*_]{1,3}'), '');

    // Remove blockquote markers (> )
    cleaned = cleaned.replaceAll(RegExp(r'^>\s*', multiLine: true), '');

    // Remove Markdown links [label](url) -> label
    cleaned = cleaned.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), (m) => m[1] ?? '');

    // Replace list bullets with a natural pause comma
    cleaned = cleaned.replaceAll(RegExp(r'^[-*+]\s+', multiLine: true), '，');
    cleaned = cleaned.replaceAll(RegExp(r'^\d+\.\s+', multiLine: true), '，');

    // Replace multiple newlines with full stop
    cleaned = cleaned.replaceAll(RegExp(r'\n+'), '。');

    // Clean any dangling punctuation
    cleaned = cleaned.replaceAll(RegExp(r'。{2,}'), '。');
    cleaned = cleaned.replaceAll(RegExp(r'，{2,}'), '，');

    return cleaned.trim();
  }

  /// Speaks the provided text via Apple's native AVSpeechSynthesizer
  Future<void> speak(
    String text, {
    double rate = 0.5,
    double pitch = 1.0,
    String lang = 'zh-CN',
    String? voiceIdentifier,
  }) async {
    final clean = cleanMarkdown(text);
    if (clean.isEmpty) return;

    try {
      await _channel.invokeMethod('speak', {
        'text': clean,
        'rate': rate,
        'pitch': pitch,
        'lang': lang,
        'voiceIdentifier': voiceIdentifier,
      });
    } catch (e) {
      debugPrint('[TtsService] Speak error: $e');
    }
  }

  /// Retrieves all Chinese / system voices available on the iOS device
  Future<List<Map<String, dynamic>>> getAvailableVoices() async {
    try {
      final list =
          await _channel.invokeListMethod<Map<dynamic, dynamic>>('getVoices');
      if (list == null) return [];
      return list.map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (e) {
      debugPrint('[TtsService] getAvailableVoices error: $e');
      return [];
    }
  }

  /// Stops current speech output immediately
  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
      onSpeakingChanged?.call(false);
    } catch (_) {}
  }

  /// Pauses current speech output
  Future<void> pause() async {
    try {
      await _channel.invokeMethod('pause');
    } catch (_) {}
  }

  /// Resumes speech output
  Future<void> resume() async {
    try {
      await _channel.invokeMethod('resume');
    } catch (_) {}
  }

  void dispose() {
    stop();
  }
}
