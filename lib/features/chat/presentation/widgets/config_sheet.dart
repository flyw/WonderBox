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
              children: [
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
}
