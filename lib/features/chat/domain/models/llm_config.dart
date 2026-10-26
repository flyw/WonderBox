class LlmConfig {
  final String baseUrl;
  final String apiKey;
  final String model;
  final double temperature;
  final String systemPrompt;

  const LlmConfig({
    this.baseUrl = 'http://127.0.0.1:58588/v1',
    this.apiKey = 'local-minicpm',
    this.model = 'MiniCPM-V-4.6',
    this.temperature = 0.7,
    this.systemPrompt = '你是一个专业的智能伴听分析助手，根据用户短句、文字输入和现场画面上下文，给出敏锐、精炼、结构清晰的分析回复。',
  });

  LlmConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    double? temperature,
    String? systemPrompt,
  }) {
    return LlmConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
      systemPrompt: systemPrompt ?? this.systemPrompt,
    );
  }
}
