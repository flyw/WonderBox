import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/network/sse_transformer.dart';
import '../../domain/models/chat_message.dart';
import '../../domain/models/llm_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final llmRemoteDataSourceProvider = Provider<LlmRemoteDataSource>((ref) {
  final dio = ref.watch(dioClientProvider);
  return LlmRemoteDataSource(dio);
});

class LlmRemoteDataSource {
  final Dio _dio;

  LlmRemoteDataSource(this._dio);

  Stream<LlmStreamChunk> streamChat({
    required List<ChatMessage> messages,
    required LlmConfig config,
    CancelToken? cancelToken,
  }) async* {
    final endpoint = config.baseUrl.endsWith('/')
        ? '${config.baseUrl}chat/completions'
        : '${config.baseUrl}/chat/completions';

    final requestMessages = [
      if (config.systemPrompt.isNotEmpty)
        {'role': 'system', 'content': config.systemPrompt},
      ...messages.map((m) => m.toApiMessage()),
    ];

    final requestBody = {
      'model': config.model,
      'messages': requestMessages,
      'temperature': config.temperature,
      'stream': true,
    };

    final headers = <String, dynamic>{
      'Content-Type': 'application/json',
      if (config.apiKey.isNotEmpty) 'Authorization': 'Bearer ${config.apiKey}',
    };

    try {
      final response = await _dio.post<ResponseBody>(
        endpoint,
        data: jsonEncode(requestBody),
        cancelToken: cancelToken,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
        ),
      );

      final stream = response.data?.stream;
      if (stream == null) {
        throw Exception('Response body stream is null');
      }

      yield* SseTransformer.parse(stream);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        yield const LlmStreamChunk(isDone: true);
        return;
      }
      final errorMsg = e.response?.data != null ? '${e.message}: ${e.response?.data}' : e.message;
      throw Exception('LLM Stream Error: $errorMsg');
    } catch (e) {
      throw Exception('Unexpected error during LLM streaming: $e');
    }
  }
}
