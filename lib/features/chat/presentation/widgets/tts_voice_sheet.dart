import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/tts_service.dart';
import '../controllers/tts_controller.dart';

class TtsVoiceSheet extends ConsumerStatefulWidget {
  const TtsVoiceSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const TtsVoiceSheet(),
    );
  }

  @override
  ConsumerState<TtsVoiceSheet> createState() => _TtsVoiceSheetState();
}

class _TtsVoiceSheetState extends ConsumerState<TtsVoiceSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ttsControllerProvider.notifier).loadAvailableVoices();
    });
  }

  void _previewVoice(String voiceId, String voiceName) {
    final ttsState = ref.read(ttsControllerProvider);
    final service = ref.read(ttsServiceProvider);
    service.speak(
      '你好，我是 WonderBox 智能伴听助手，很高兴为你服务。',
      rate: ttsState.rate,
      pitch: ttsState.pitch,
      voiceIdentifier: voiceId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ttsState = ref.watch(ttsControllerProvider);
    final notifier = ref.read(ttsControllerProvider.notifier);
    final voices = ttsState.availableVoices;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.record_voice_over_rounded,
                      color: theme.colorScheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TTS 语音音色设置',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '已开启 Siri / 高保真（Premium）原生音色优先',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // Pitch and Rate Sliders
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '语速调节 (Rate)',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${(ttsState.rate * 2.0).toStringAsFixed(1)}x',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: ttsState.rate,
                        min: 0.3,
                        max: 0.8,
                        divisions: 10,
                        onChanged: (val) {
                          notifier.setRate(val);
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '音调微调 (Pitch)',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            ttsState.pitch > 1.05
                                ? '偏轻快 (${ttsState.pitch.toStringAsFixed(2)})'
                                : (ttsState.pitch < 0.95
                                    ? '偏沉稳 (${ttsState.pitch.toStringAsFixed(2)})'
                                    : '标准原声 (1.0)'),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: ttsState.pitch,
                        min: 0.7,
                        max: 1.3,
                        divisions: 12,
                        onChanged: (val) {
                          notifier.setPitch(val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Voice List Section
                Row(
                  children: [
                    const Icon(Icons.mic, size: 16),
                    const SizedBox(width: 6),
                    const Text(
                      '设备可用中文音色列表',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Text(
                      '共 ${voices.length} 个音色',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (voices.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    child: const Text('正在查询设备系统音色...'),
                  )
                else
                  ...voices.map((v) {
                    final id = v['identifier'] as String? ?? '';
                    final name = v['name'] as String? ?? '系统语音';
                    final lang = v['language'] as String? ?? 'zh-CN';
                    final quality = v['quality'] as int? ?? 1;
                    final isSiri = name.toLowerCase().contains('siri') ||
                        id.toLowerCase().contains('siri');
                    final isSelected = id == ttsState.selectedVoiceId;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        leading: Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        title: Row(
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight:
                                    isSelected ? FontWeight.bold : FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (isSiri)
                              _buildBadge(context, 'Siri 高保真', Colors.purple)
                            else if (quality == 3)
                              _buildBadge(context, 'Premium 超高清', Colors.amber.shade800)
                            else if (quality == 2)
                              _buildBadge(context, 'Enhanced 增强', Colors.blue)
                            else
                              _buildBadge(context, '标准', Colors.grey),
                          ],
                        ),
                        subtitle: Text(
                          '$lang · ${id.split('.').last}',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: TextButton.icon(
                          icon: const Icon(Icons.volume_up, size: 16),
                          label: const Text('试听', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () => _previewVoice(id, name),
                        ),
                        onTap: () {
                          notifier.selectVoice(id, name);
                          _previewVoice(id, name);
                        },
                      ),
                    );
                  }),

                const SizedBox(height: 12),
                // System Download Tips
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blue, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '提示：前往 iPhone「设置」→「辅助功能」→「朗读内容」→「声音」→「中文」，可免费下载苹果官方 Siri 或婷婷的增强版/高保真（Premium）高音质数据包。',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
