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

    final hasImages = messages.any((m) => m.imagePath != null && m.imagePath!.isNotEmpty);

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

      // Read response error body from byte stream if available
      String? errorBody;
      final responseData = e.response?.data;
      if (responseData is ResponseBody) {
        try {
          final bytes = await responseData.stream.expand((chunk) => chunk).toList();
          errorBody = utf8.decode(bytes);
        } catch (_) {}
      } else if (responseData != null) {
        errorBody = responseData.toString();
      }

      final fullError = errorBody ?? e.message ?? '';

      // If the error is due to image input not being supported (e.g. text-only model or missing mmproj),
      // gracefully retry once with text-only message format so the conversation continues seamlessly.
      if (hasImages &&
          (fullError.contains('image input is not supported') ||
              fullError.contains('mmproj') ||
              fullError.contains('image_url') ||
              e.response?.statusCode == 400 ||
              e.response?.statusCode == 500)) {
        yield const LlmStreamChunk(
          reasoning: '【多模态视界兼容】当前目标模型未挂载视觉投影(mmproj)或为纯文本模型，自动降级为语义分析。\n',
        );

        final textOnlyMessages = [
          if (config.systemPrompt.isNotEmpty)
            {'role': 'system', 'content': config.systemPrompt},
          ...messages.map((m) => {
                'role': m.role.name,
                'content': m.imagePath != null && m.imagePath!.isNotEmpty
                    ? '${m.content} [现场画面已捕获]'
                    : m.content,
              }),
        ];

        try {
          final fallbackResponse = await _dio.post<ResponseBody>(
            endpoint,
            data: jsonEncode({
              'model': config.model,
              'messages': textOnlyMessages,
              'temperature': config.temperature,
              'stream': true,
            }),
            cancelToken: cancelToken,
            options: Options(
              headers: headers,
              responseType: ResponseType.stream,
            ),
          );

          final fallbackStream = fallbackResponse.data?.stream;
          if (fallbackStream != null) {
            yield* SseTransformer.parse(fallbackStream);
            return;
          }
        } catch (_) {
          // If fallback also fails, rethrow original error below
        }
      }

      if (e.type == DioExceptionType.connectionError ||
          fullError.contains('Connection refused') ||
          fullError.contains('errno = 61')) {
        throw Exception(
          '无法连接到模型推理服务 ($endpoint)。若使用本地端侧模型，请确保服务已启动；若在手机端体验，请在设置中配置电脑局域网 IP 或云端 API Key。',
        );
      }

      throw Exception('LLM Stream Error: ${errorBody ?? e.message}');
    } catch (e) {
      throw Exception('Unexpected error during LLM streaming: $e');
    }
  }
}
