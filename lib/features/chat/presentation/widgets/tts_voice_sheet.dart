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
  String _selectedFilter = 'all'; // 'all', 'en', 'zh', 'other'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ttsControllerProvider.notifier).loadAvailableVoices();
    });
  }

  bool _isSiriVoice4(Map<String, dynamic> v) {
    final name = (v['name'] as String? ?? '').toLowerCase();
    final id = (v['identifier'] as String? ?? '').toLowerCase();
    final lang = (v['language'] as String? ?? '').toLowerCase();
    final isEn = lang.startsWith('en');
    final is4 = name.contains('voice 4') ||
        name.contains('声音 4') ||
        name.contains('voice4') ||
        id.contains('voice_4') ||
        id.contains('voice4') ||
        id.contains('voice-4') ||
        ((name.contains('siri') || id.contains('siri')) &&
            (name.contains('4') || id.contains('4')));
    return isEn && is4;
  }

  void _previewVoice(String voiceId, String voiceName, String lang) {
    final ttsState = ref.read(ttsControllerProvider);
    final service = ref.read(ttsServiceProvider);
    final isEn = lang.toLowerCase().startsWith('en');
    final text = isEn
        ? 'Hello, I am WonderBox AI assistant, powered by Siri American voice. Nice to meet you!'
        : '你好，我是 WonderBox 智能伴听助手，很高兴为你服务。';
    service.speak(
      text,
      rate: ttsState.rate,
      pitch: ttsState.pitch,
      voiceIdentifier: voiceId,
      lang: isEn ? 'en-US' : 'zh-CN',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ttsState = ref.watch(ttsControllerProvider);
    final notifier = ref.read(ttsControllerProvider.notifier);
    final allVoices = ttsState.availableVoices;

    final enVoices = allVoices.where((v) {
      final lang = (v['language'] as String? ?? '').toLowerCase();
      return lang.startsWith('en');
    }).toList();

    final zhVoices = allVoices.where((v) {
      final lang = (v['language'] as String? ?? '').toLowerCase();
      return lang.startsWith('zh');
    }).toList();

    final otherVoices = allVoices.where((v) {
      final lang = (v['language'] as String? ?? '').toLowerCase();
      return !lang.startsWith('en') && !lang.startsWith('zh');
    }).toList();

    List<Map<String, dynamic>> displayedVoices;
    if (_selectedFilter == 'en') {
      displayedVoices = enVoices;
    } else if (_selectedFilter == 'zh') {
      displayedVoices = zhVoices;
    } else if (_selectedFilter == 'other') {
      displayedVoices = otherVoices;
    } else {
      displayedVoices = allVoices;
    }

    final hasSiriVoice4 = allVoices.any(_isSiriVoice4);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
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
                        'TTS 语音与音色设置',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '支持 Siri Voice 4 (美国口音) · 智能双语朗读',
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
                const SizedBox(height: 14),

                // Status & Download Guidance Banner
                if (hasSiriVoice4)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            color: Colors.deepPurple, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '已检测到 Siri Voice 4 (美国口音)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepPurple,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '系统已优先选中此音色。中文文本将自动音译为地道美式发音，英文输出将享受真人原生语调。',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.deepPurple.shade900,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.amber.shade900, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              '如何添加 Siri Voice 4 (美国口音)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '打开 iPhone「设置」→「辅助功能」→「朗读内容」→「声音」→「英语」→「Siri」→ 下载「声音 4 (Voice 4)」。下载完成后返回点击下方「刷新检测」，即可自动接入！',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.amber.shade900,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Language Filter Tabs & Header
                Row(
                  children: [
                    const Icon(Icons.mic, size: 16),
                    const SizedBox(width: 6),
                    const Text(
                      '可用音色列表',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('刷新检测', style: TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                      onPressed: () {
                        ref.read(ttsControllerProvider.notifier).loadAvailableVoices();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Filter chips: [ 全部 | 🇺🇸 英语 | 🇨🇳 中文 | 🌐 其他 ]
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip(
                        context,
                        label: '全部 (${allVoices.length})',
                        selected: _selectedFilter == 'all',
                        onSelected: () => setState(() => _selectedFilter = 'all'),
                      ),
                      const SizedBox(width: 6),
                      _buildFilterChip(
                        context,
                        label: '🇺🇸 英语 (${enVoices.length})',
                        selected: _selectedFilter == 'en',
                        onSelected: () => setState(() => _selectedFilter = 'en'),
                      ),
                      const SizedBox(width: 6),
                      _buildFilterChip(
                        context,
                        label: '🇨🇳 中文 (${zhVoices.length})',
                        selected: _selectedFilter == 'zh',
                        onSelected: () => setState(() => _selectedFilter = 'zh'),
                      ),
                      if (otherVoices.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _buildFilterChip(
                          context,
                          label: '🌐 其他 (${otherVoices.length})',
                          selected: _selectedFilter == 'other',
                          onSelected: () => setState(() => _selectedFilter = 'other'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                if (displayedVoices.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    child: Text(
                      allVoices.isEmpty ? '正在查询设备系统音色...' : '当前分类暂无可用的音色包',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  ...displayedVoices.map((v) {
                    final id = v['identifier'] as String? ?? '';
                    final rawName = v['name'] as String? ?? '系统语音';
                    final lang = v['language'] as String? ?? 'en-US';
                    final quality = v['quality'] as int? ?? 1;
                    final isSiri4 = _isSiriVoice4(v);
                    final isSiri = isSiri4 ||
                        rawName.toLowerCase().contains('siri') ||
                        id.toLowerCase().contains('siri');
                    final isSelected = id == ttsState.selectedVoiceId;

                    // Polish display name
                    String displayName = rawName;
                    if (isSiri4) {
                      displayName = 'Siri (Voice 4) · 美国口音';
                    } else if (rawName.toLowerCase() == 'voice 4' || rawName.toLowerCase() == '声音 4') {
                      displayName = 'Siri (Voice 4) · 美国口音';
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                            : (isSiri4
                                ? Colors.deepPurple.withValues(alpha: 0.08)
                                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : (isSiri4
                                  ? Colors.deepPurple.withValues(alpha: 0.4)
                                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                          width: isSelected ? 1.5 : (isSiri4 ? 1.2 : 1.0),
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
                            Flexible(
                              child: Text(
                                displayName,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight:
                                      isSelected || isSiri4 ? FontWeight.bold : FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (isSiri4)
                              _buildBadge(context, '首选 推荐', Colors.deepPurple)
                            else if (isSiri)
                              _buildBadge(context, 'Siri 高保真', Colors.purple)
                            else if (quality == 3)
                              _buildBadge(context, 'Premium 超清', Colors.amber.shade800)
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
                          onPressed: () => _previewVoice(id, displayName, lang),
                        ),
                        onTap: () {
                          notifier.selectVoice(id, displayName);
                          _previewVoice(id, displayName, lang);
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
                          '音色提示：本列表完全读取 iPhone「设置」→「辅助功能」→「朗读内容」→「声音」中下载的系统及 Siri 语音包。所有发音人均在本地实时离线合成，无隐私泄漏及网络延迟。',
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

  Widget _buildFilterChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    final theme = Theme.of(context);
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
        ),
      ),
      selected: selected,
      selectedColor: theme.colorScheme.primary,
      backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      onSelected: (_) => onSelected(),
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
