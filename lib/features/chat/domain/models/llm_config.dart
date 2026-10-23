class LlmConfig {
  final String baseUrl;
  final String apiKey;
  final String model;
  final double temperature;
  final String systemPrompt;

  const LlmConfig({
    this.baseUrl = 'https://api.deepseek.com',
    this.apiKey = '',
    this.model = 'deepseek-chat',
    this.temperature = 0.7,
    this.systemPrompt = 'You are a helpful and concise AI assistant.',
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
