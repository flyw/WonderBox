import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonder_box/features/chat/data/services/jev_style_model_manager.dart';
import 'package:wonder_box/features/chat/domain/models/chat_message.dart';
import 'package:wonder_box/features/chat/domain/models/llm_config.dart';
import 'package:wonder_box/features/chat/domain/services/topic_relevance_judge.dart';

void main() {
  group('TopicRelevanceJudge Tests', () {
    late Dio mockDio;
    late TopicRelevanceJudge judge;

    setUp(() {
      mockDio = Dio();
      judge = TopicRelevanceJudge(mockDio, JevStyleModelManager());
    });

    test('ignores micro-fillers and single character sounds', () async {
      final isRelevant = await judge.judgeRelevance(
        candidatePhrase: '嗯',
        conversationHistory: [],
        config: const LlmConfig(),
      );
      expect(isRelevant, false);
    });

    test('ignores verbal fillers like 好的好的 and 哈喽', () async {
      final isRelevant = await judge.judgeRelevance(
        candidatePhrase: '好的好的',
        conversationHistory: [],
        config: const LlmConfig(),
      );
      expect(isRelevant, false);
    });

    test('accepts substantial question in empty conversation', () async {
      final isRelevant = await judge.judgeRelevance(
        candidatePhrase: '请帮我分析一下这个项目的架构',
        conversationHistory: [],
        config: const LlmConfig(),
      );
      expect(isRelevant, true);
    });

    test('accepts query when config has no api key and phrase is substantive', () async {
      final isRelevant = await judge.judgeRelevance(
        candidatePhrase: '这个方案在移动端上的性能表现如何？',
        conversationHistory: [
          ChatMessage(
            id: '1',
            role: MessageRole.user,
            content: '我们正在讨论 WonderBox 的架构设计。',
            createdAt: DateTime.now(),
          ),
        ],
        config: const LlmConfig(apiKey: ''),
      );
      expect(isRelevant, true);
    });
  });
}
