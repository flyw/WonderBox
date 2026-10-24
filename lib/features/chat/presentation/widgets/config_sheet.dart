import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/chat_controller.dart';

class ConfigSheet extends ConsumerStatefulWidget {
  const ConfigSheet({super.key});

  @override
  ConsumerState<ConfigSheet> createState() => _ConfigSheetState();
}

class _ConfigSheetState extends ConsumerState<ConfigSheet> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;

  @override
  void initState() {
    super.initState();
    final config = ref.read(llmConfigProvider);
    _baseUrlController = TextEditingController(text: config.baseUrl);
    _apiKeyController = TextEditingController(text: config.apiKey);
    _modelController = TextEditingController(text: config.model);
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _applyPreset(String name) {
    if (name == 'DeepSeek') {
      _baseUrlController.text = 'https://api.deepseek.com';
      _modelController.text = 'deepseek-chat';
    } else if (name == 'DeepSeek R1') {
      _baseUrlController.text = 'https://api.deepseek.com';
      _modelController.text = 'deepseek-reasoner';
    } else if (name == 'OpenAI') {
      _baseUrlController.text = 'https://api.openai.com/v1';
      _modelController.text = 'gpt-4o-mini';
    } else if (name == 'MiniCPM-V-4.6 (本地端侧)') {
      _baseUrlController.text = 'http://127.0.0.1:58588/v1';
      _modelController.text = 'MiniCPM-V-4.6';
      _apiKeyController.text = 'local-minicpm';
    } else if (name == 'Ollama (Local)') {
      _baseUrlController.text = 'http://localhost:11434/v1';
      _modelController.text = 'llama3.2';
    }
    setState(() {});
  }

  void _save() {
    ref.read(llmConfigProvider.notifier).updateConfig(
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.tune),
                const SizedBox(width: 8),
                Text('LLM Provider Settings', style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.bolt, size: 16, color: Colors.amber),
                  label: const Text('MiniCPM-V-4.6 (本地端侧)'),
                  onPressed: () => _applyPreset('MiniCPM-V-4.6 (本地端侧)'),
                ),
                ActionChip(
                  label: const Text('DeepSeek V3'),
                  onPressed: () => _applyPreset('DeepSeek'),
                ),
                ActionChip(
                  label: const Text('DeepSeek R1'),
                  onPressed: () => _applyPreset('DeepSeek R1'),
                ),
                ActionChip(
                  label: const Text('OpenAI'),
                  onPressed: () => _applyPreset('OpenAI'),
                ),
                ActionChip(
                  label: const Text('Ollama (Local)'),
                  onPressed: () => _applyPreset('Ollama (Local)'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://api.deepseek.com',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: 'Model Name',
                hintText: 'deepseek-chat',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _apiKeyController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: 'sk-...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.memory, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        '端侧本地模型状态 (On-Device Models)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildModelRow('MiniCPM-V-4.6 (多模态视界)', '504 MB · 视觉与语义理解', true),
                  const SizedBox(height: 4),
                  _buildModelRow('Camera Perception', '现场画面读取与多模态对齐', true),
                  const SizedBox(height: 4),
                  _buildModelRow('Jev-Style-0.8B (GGUF)', '504 MB · 意图判别与路由', true),
                  const SizedBox(height: 4),
                  _buildModelRow('Streaming-Paraformer', '226 MB · 实时打字机语音', true),
                  const SizedBox(height: 4),
                  _buildModelRow('TEN VAD (Agora)', '324 KB · 高灵敏切句防吞音', true),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              child: const Text('Save Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelRow(String name, String desc, bool ready) {
    return Row(
      children: [
        Icon(
          ready ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 14,
          color: ready ? Colors.green : Colors.grey,
        ),
        const SizedBox(width: 6),
        Text(
          name,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        Text(
          desc,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }
}
