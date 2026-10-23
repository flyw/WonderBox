import 'package:dio/dio.dart';
import '../../../../core/network/sse_transformer.dart';
import '../models/chat_message.dart';
import '../models/llm_config.dart';

abstract class ChatRepository {
  Stream<LlmStreamChunk> streamChat({
    required List<ChatMessage> messages,
    required LlmConfig config,
    CancelToken? cancelToken,
  });
}
