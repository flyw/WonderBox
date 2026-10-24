import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';
import '../../data/services/jev_style_model_manager.dart';
import '../../data/services/local_minicpm_service.dart';
import '../../domain/models/chat_message.dart';
import '../../domain/models/llm_config.dart';

final topicRelevanceJudgeProvider = Provider<TopicRelevanceJudge>((ref) {
  final dio = ref.watch(dioClientProvider);
  final jevModelManager = ref.watch(jevStyleModelManagerProvider);
  final localMiniCpmService = ref.watch(localMiniCpmServiceProvider);
  return TopicRelevanceJudge(dio, jevModelManager, localMiniCpmService: localMiniCpmService);
});

class TopicRelevanceJudge {
  final Dio _dio;
  final JevStyleModelManager _jevModelManager;
  final LocalMiniCpmService? localMiniCpmService;

  TopicRelevanceJudge(
    this._dio,
    this._jevModelManager, {
    this.localMiniCpmService,
  });

  JevStyleModelManager get jevModelManager => _jevModelManager;

  /// Judges whether [candidatePhrase] is relevant to the ongoing [conversationHistory].
  /// Uses Jev-Style-0.8B Decision model when available, with fast remote LLM fallback.
  Future<bool> judgeRelevance({
    required String candidatePhrase,
    required List<ChatMessage> conversationHistory,
    required LlmConfig config,
    CancelToken? cancelToken,
  }) async {
    final phrase = candidatePhrase.trim();
    // Ignore micro-fillers or extremely short murmurs
    if (phrase.length < 2) return false;

    // Filter out common ambient verbal fillers
    final lower = phrase.toLowerCase();
    if (const ['嗯', '啊', '哦', '好的好的', '喂', '喂喂', '哈喽'].contains(lower)) {
      return false;
    }

    // If conversation is empty, any substantive phrase (>= 3 chars) is considered relevant as topic starter
    if (conversationHistory.isEmpty) {
      return phrase.length >= 3;
    }

    // Resolve endpoint and credentials (auto route to local MiniCPM server if available)
    String targetBaseUrl = config.baseUrl;
    String targetApiKey = config.apiKey;
    String targetModel = config.model;

    if (targetApiKey.isEmpty && localMiniCpmService != null) {
      final isLocalUp = await localMiniCpmService!.isServerRunning();
      if (isLocalUp) {
        targetBaseUrl = LocalMiniCpmService.defaultLocalBaseUrl;
        targetApiKey = 'local-minicpm';
        targetModel = LocalMiniCpmService.defaultModelName;
      }
    }

    // If still no API Key or local server, fallback to heuristic acceptance
    if (targetApiKey.isEmpty) {
      return phrase.length >= 3;
    }

    // Prepare concise recent context (last 4 messages)
    final recentMessages = conversationHistory.length > 4
        ? conversationHistory.sublist(conversationHistory.length - 4)
        : conversationHistory;

    final contextBuffer = StringBuffer();
    for (final m in recentMessages) {
      final role = m.role == MessageRole.user ? 'User' : 'Assistant';
      final snippet = m.content.length > 120
          ? '${m.content.substring(0, 120)}...'
          : m.content;
      contextBuffer.writeln('$role: $snippet');
    }

    final judgePrompt = '''
你是一个基于 Jev-Style-0.8B 决策规范的【意图相关性裁判】。
请根据当前会话的主题与最新上下文，判断用户刚说的这句话是否属于与当前会话相关的提问、探讨、追问、补充或指令。

【当前会话最新上下文】：
$contextBuffer

【刚捕获的用户语音短句】：
"$phrase"

【判定准则】：
- 如果是在围绕上述会话内容继续提问、发表意见、追问细节或下达指令，判定为相关（YES）。
- 如果是日常生活闲聊（如接电话、喊人、喝水、打招呼、向旁人讲话等非会话内容），判定为不相关（NO）。

请只输出一个词：YES 或 NO（不要输出任何其他多余文字或标点）。
''';

    final endpoint = targetBaseUrl.endsWith('/')
        ? '${targetBaseUrl}chat/completions'
        : '$targetBaseUrl/chat/completions';

    final requestBody = {
      'model': targetModel,
      'messages': [
        {
          'role': 'system',
          'content': '你是一个高精度话题相关性二分类器。严格按要求仅回复 YES 或 NO。',
        },
        {'role': 'user', 'content': judgePrompt},
      ],
      'temperature': 0.0,
      'max_tokens': 160,
      'stream': false,
    };

    final headers = <String, dynamic>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $targetApiKey',
    };

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        endpoint,
        data: jsonEncode(requestBody),
        cancelToken: cancelToken,
        options: Options(
          headers: headers,
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

      final data = response.data;
      if (data != null && data['choices'] != null && (data['choices'] as List).isNotEmpty) {
        final message = data['choices'][0]['message'] as Map<String, dynamic>? ?? {};
        final content = (message['content'] as String? ?? '').trim().toUpperCase();
        final reasoning = (message['reasoning_content'] as String? ?? '').trim().toUpperCase();

        if (content.contains('YES') || (content.isEmpty && reasoning.contains('YES'))) {
          return true;
        }
        if (content.contains('NO')) {
          return false;
        }
        return content.contains('YES');
      }

      // Default safe fallback if structure is unexpected
      return false;
    } catch (e) {
      // In case of network timeout or judge error, fallback to length check to avoid blocking user
      return phrase.length >= 4;
    }
  }
}
