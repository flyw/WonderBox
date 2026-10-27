import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../voice/data/services/qwen3_tts_service.dart';
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
  String _selectedFilter = 'all'; // 'all', 'en', 'zh'

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
    final lang = (v['language'] as String? ?? '').toLowerCase().replaceAll('_', '-');
    final isEn = lang == 'en-us' || lang.startsWith('en-us');
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

  void _showEndpointConfigDialog(BuildContext context) {
    final ttsState = ref.read(ttsControllerProvider);
    final notifier = ref.read(ttsControllerProvider.notifier);
    final controller = TextEditingController(
      text: ttsState.customEndpoint ?? '',
    );
    String? statusMsg;
    bool isTesting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.hub_rounded, size: 20, color: Colors.deepPurple),
                SizedBox(width: 8),
                Text('配置 Qwen3-TTS 服务地址', style: TextStyle(fontSize: 16)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '支持本地端侧端口（默认 127.0.0.1:58588）或同局域网 Mac/PC 部署的 speech-server 服务：',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: '服务请求 URL',
                    hintText: 'http://127.0.0.1:58588/v1/audio/speech',
                    prefixIcon: const Icon(Icons.link, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton.icon(
                      icon: isTesting
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_check, size: 14),
                      label: const Text('测试连接', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: isTesting
                          ? null
                          : () async {
                              setDialogState(() {
                                isTesting = true;
                                statusMsg = null;
                              });
                              final target = controller.text.trim().isEmpty
                                  ? 'http://127.0.0.1:58588/v1/audio/speech'
                                  : controller.text.trim();
                              final qwen3Service = ref.read(qwen3TtsServiceProvider);
                              final res = await qwen3Service.testConnection(target);
                              setDialogState(() {
                                isTesting = false;
                                statusMsg = res.ok
                                    ? '✅ ${res.message}'
                                    : '❌ ${res.message}';
                              });
                            },
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      child: const Text('恢复默认', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        controller.clear();
                        setDialogState(() {
                          statusMsg = '已重置为端侧默认服务';
                        });
                      },
                    ),
                  ],
                ),
                if (statusMsg != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    statusMsg!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusMsg!.startsWith('✅') ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  notifier.setCustomEndpoint(controller.text.trim());
                  Navigator.of(ctx).pop();
                },
                child: const Text('保存生效'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _previewVoice(String voiceId, String voiceName, String lang) {
    final ttsState = ref.read(ttsControllerProvider);
    final service = ref.read(ttsServiceProvider);
    final isEn = lang.toLowerCase().replaceAll('_', '-').startsWith('en-us') ||
        lang.toLowerCase().startsWith('en');
    final text = isEn
        ? 'Hello, I am WonderBox AI assistant, powered by Siri American voice. Nice to meet you!'
        : '你好，我是 WonderBox 智能伴听助手，很高兴为你服务。';
    service.speak(
      text,
      engine: TtsEngine.systemApple,
      rate: ttsState.rate,
      pitch: ttsState.pitch,
      voiceIdentifier: voiceId,
      lang: isEn ? 'en-US' : 'zh-CN',
    );
  }

  void _previewQwen3Voice(String voiceId) {
    final ttsState = ref.read(ttsControllerProvider);
    final service = ref.read(ttsServiceProvider);
    const text = '你好，我是 WonderBox 搭载的 Qwen3-TTS 0.6B 本地端侧大模型音色，很高兴与你实时对话。';
    service.speak(
      text,
      engine: TtsEngine.qwen3Tts,
      qwen3Voice: voiceId,
      rate: ttsState.rate,
      pitch: ttsState.pitch,
      customBaseUrl: ttsState.customEndpoint,
      onError: (err) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(err, style: const TextStyle(fontSize: 12))),
              ],
            ),
            backgroundColor: Colors.deepPurple.shade800,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ttsState = ref.watch(ttsControllerProvider);
    final notifier = ref.read(ttsControllerProvider.notifier);
    final allVoices = ttsState.availableVoices;

    final enVoices = allVoices.where((v) {
      final lang = (v['language'] as String? ?? '').toLowerCase().replaceAll('_', '-');
      return lang == 'en-us' || lang.startsWith('en-us');
    }).toList();

    final zhVoices = allVoices.where((v) {
      final lang = (v['language'] as String? ?? '').toLowerCase().replaceAll('_', '-');
      return lang == 'zh-cn' || lang.startsWith('zh-cn');
    }).toList();

    List<Map<String, dynamic>> displayedVoices;
    if (_selectedFilter == 'en') {
      displayedVoices = enVoices;
    } else if (_selectedFilter == 'zh') {
      displayedVoices = zhVoices;
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
                        '仅保留 US 英语 (en-US) 与 CN 中文 (zh-CN) · Siri Voice 4 优先',
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
                // TTS Engine Switch
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SegmentedButton<TtsEngine>(
                    segments: const [
                      ButtonSegment<TtsEngine>(
                        value: TtsEngine.qwen3Tts,
                        icon: Icon(Icons.auto_awesome, size: 16),
                        label: Text('⚡ Qwen3-TTS (0.6B Q4)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      ButtonSegment<TtsEngine>(
                        value: TtsEngine.systemApple,
                        icon: Icon(Icons.apple, size: 16),
                        label: Text('🍎 Apple 系统音色', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                    selected: {ttsState.engine},
                    onSelectionChanged: (newSelection) {
                      notifier.setEngine(newSelection.first);
                    },
                  ),
                ),

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
                        onChangeEnd: (val) {
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
                        onChangeEnd: (val) {
                          notifier.setPitch(val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                if (ttsState.engine == TtsEngine.qwen3Tts) ...[
                  // Qwen3 Model Status & Download Box
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.deepPurple.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.memory, color: Colors.deepPurple, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '千问 Qwen3-TTS 0.6B 本地端侧大模型',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Text(
                                    '4-bit GGUF 量化 · 端侧神经语音合成 · 自然拟人表达',
                                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            if (ttsState.isQwen3Downloaded)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle, size: 12, color: Colors.green),
                                    SizedBox(width: 4),
                                    Text(
                                      '已就绪',
                                      style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        if (!ttsState.isQwen3Downloaded) ...[
                          const SizedBox(height: 10),
                          if (ttsState.qwen3DownloadProgress > 0 && ttsState.qwen3DownloadProgress < 1.0) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: ttsState.qwen3DownloadProgress,
                                backgroundColor: Colors.deepPurple.withValues(alpha: 0.1),
                                color: Colors.deepPurple,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              ttsState.qwen3DownloadStatus ?? '正在下载...',
                              style: const TextStyle(fontSize: 11, color: Colors.deepPurple),
                            ),
                          ] else ...[
                            Row(
                              children: [
                                Text(
                                  ttsState.qwen3DownloadStatus ?? '模型大小约 378 MB (4-bit Q4)',
                                  style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                                ),
                                const Spacer(),
                                FilledButton.tonalIcon(
                                  icon: const Icon(Icons.download, size: 14),
                                  label: const Text('下载本地模型', style: TextStyle(fontSize: 12)),
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  ),
                                  onPressed: () {
                                    notifier.downloadQwen3Model();
                                  },
                                ),
                              ],
                            ),
                          ],
                        ],
                        const SizedBox(height: 10),
                        const Divider(height: 1),
                        const SizedBox(height: 8),

                        // Endpoint & Service status row
                        Row(
                          children: [
                            Icon(
                              ttsState.isServerConnected == true
                                  ? Icons.check_circle_rounded
                                  : (ttsState.isServerConnected == false
                                      ? Icons.cancel_rounded
                                      : Icons.radio_button_unchecked),
                              size: 14,
                              color: ttsState.isServerConnected == true
                                  ? Colors.green
                                  : (ttsState.isServerConnected == false ? Colors.orange : Colors.grey),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                ttsState.customEndpoint != null
                                    ? '自定义服务: ${ttsState.customEndpoint}'
                                    : '端侧服务: 127.0.0.1:58588',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.settings_ethernet, size: 13),
                              label: const Text('配置/测试', style: TextStyle(fontSize: 11)),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                              ),
                              onPressed: () => _showEndpointConfigDialog(context),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Qwen3 Presets Section
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'Qwen3-TTS 拟真大模型声线',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                  ...Qwen3TtsService.presetVoices.map((voice) {
                    final isSelected = ttsState.qwen3Voice == voice.id;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.deepPurple.withValues(alpha: 0.12)
                            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? Colors.deepPurple
                              : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: isSelected
                              ? Colors.deepPurple.withValues(alpha: 0.2)
                              : theme.colorScheme.surfaceContainerHighest,
                          child: Text(voice.iconEmoji, style: const TextStyle(fontSize: 16)),
                        ),
                        title: Row(
                          children: [
                            Text(
                              voice.name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                color: isSelected ? Colors.deepPurple : null,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (voice.id == 'vivian')
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('推荐首选', style: TextStyle(fontSize: 9.5, color: Colors.deepPurple, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          voice.description,
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.volume_up, size: 14),
                              label: const Text('试听', style: TextStyle(fontSize: 11)),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () => _previewQwen3Voice(voice.id),
                            ),
                            Icon(
                              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                              color: isSelected ? Colors.deepPurple : theme.colorScheme.onSurfaceVariant,
                              size: 18,
                            ),
                          ],
                        ),
                        onTap: () {
                          notifier.setQwen3Voice(voice.id);
                          _previewQwen3Voice(voice.id);
                        },
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                ] else ...[
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

                // Filter chips: [ 全部 | 🇺🇸 US 英语 | 🇨🇳 CN 中文 ]
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
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        context,
                        label: '🇺🇸 US 英语 (${enVoices.length})',
                        selected: _selectedFilter == 'en',
                        onSelected: () => setState(() => _selectedFilter = 'en'),
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        context,
                        label: '🇨🇳 CN 中文 (${zhVoices.length})',
                        selected: _selectedFilter == 'zh',
                        onSelected: () => setState(() => _selectedFilter = 'zh'),
                      ),
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
