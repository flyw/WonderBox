import 'dart:async';
import 'dart:convert';

/// Represents a parsed token piece from an LLM stream.
class LlmStreamChunk {
  final String? content;
  final String? reasoning;
  final bool isDone;

  const LlmStreamChunk({
    this.content,
    this.reasoning,
    this.isDone = false,
  });
}

/// Transforms raw byte chunks from Dio response into [LlmStreamChunk] stream.
class SseTransformer {
  static Stream<LlmStreamChunk> parse(Stream<List<int>> byteStream) async* {
    String buffer = '';

    await for (final rawBytes in byteStream) {
      final decoded = utf8.decode(rawBytes, allowMalformed: true);
      buffer += decoded;

      final lines = buffer.split('\n');
      // Keep trailing incomplete line in buffer
      buffer = lines.removeLast();

      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty) continue;
        if (!line.startsWith('data:')) continue;

        final data = line.replaceFirst('data:', '').trim();
        if (data == '[DONE]') {
          yield const LlmStreamChunk(isDone: true);
          return;
        }

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List<dynamic>?;
          if (choices == null || choices.isEmpty) continue;

          final firstChoice = choices[0] as Map<String, dynamic>;
          final delta = firstChoice['delta'] as Map<String, dynamic>?;

          if (delta != null) {
            final content = delta['content'] as String?;
            // Reasoning/Thinking field commonly used by DeepSeek R1 / o-series
            final reasoning = (delta['reasoning_content'] ?? delta['reasoning']) as String?;

            if ((content != null && content.isNotEmpty) || (reasoning != null && reasoning.isNotEmpty)) {
              yield LlmStreamChunk(
                content: content,
                reasoning: reasoning,
              );
            }
          }
        } catch (_) {
          // Skip malformed SSE lines safely
        }
      }
    }

    // Flush any leftover buffer if it ends with [DONE]
    if (buffer.trim() == 'data: [DONE]') {
      yield const LlmStreamChunk(isDone: true);
    }
  }
}
