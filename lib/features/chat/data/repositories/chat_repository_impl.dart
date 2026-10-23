import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/sse_transformer.dart';
import '../../domain/models/chat_message.dart';
import '../../domain/models/llm_config.dart';
import '../../domain/repositories/chat_repository.dart';
import '../datasources/llm_remote_datasource.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final remoteDataSource = ref.watch(llmRemoteDataSourceProvider);
  return ChatRepositoryImpl(remoteDataSource);
});

class ChatRepositoryImpl implements ChatRepository {
  final LlmRemoteDataSource _remoteDataSource;

  ChatRepositoryImpl(this._remoteDataSource);

  @override
  Stream<LlmStreamChunk> streamChat({
    required List<ChatMessage> messages,
    required LlmConfig config,
    CancelToken? cancelToken,
  }) {
    return _remoteDataSource.streamChat(
      messages: messages,
      config: config,
      cancelToken: cancelToken,
    );
  }
}
