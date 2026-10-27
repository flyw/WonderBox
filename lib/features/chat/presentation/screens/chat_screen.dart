import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../camera/presentation/controllers/camera_controller.dart';
import '../../../camera/presentation/widgets/camera_config_bar.dart';
import '../../../camera/presentation/widgets/camera_preview_floating.dart';
import '../../../camera/presentation/widgets/camera_toggle_pill.dart';
import '../controllers/ambient_assistant_controller.dart';
import '../controllers/chat_controller.dart';
import '../controllers/tts_controller.dart';
import '../widgets/ambient_listening_pill.dart';
import '../widgets/stop_speaking_button.dart';
import '../widgets/tts_toggle_pill.dart';
import '../widgets/vad_distance_bar.dart';
import '../widgets/chat_input_box.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  static const _screenChannel = MethodChannel('wonderbox/screen');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _keepScreenOn();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cameraControllerProvider.notifier).initialize();
      ref.read(ambientAssistantProvider.notifier).startAmbientListening();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _keepScreenOn();
    }
  }

  void _keepScreenOn() {
    try {
      _screenChannel.invokeMethod('keepScreenOn');
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatControllerProvider);
    final ttsState = ref.watch(ttsControllerProvider);
    final theme = Theme.of(context);

    // Auto scroll when messages update
    ref.listen(chatControllerProvider, (prev, next) {
      if (prev?.messages.length != next.messages.length ||
          next.isStreaming) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('WonderBox AI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(
              'MiniCPM-V-4.6 · 原生端侧协同',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 2),
            child: CameraTogglePill(),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 2),
            child: AmbientListeningPill(),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 2),
            child: TtsTogglePill(),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear Chat',
            onPressed: chatState.messages.isEmpty
                ? null
                : () {
                    ref.read(chatControllerProvider.notifier).clearChat();
                  },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const AmbientStatusBar(),
              Expanded(
                child: chatState.messages.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.auto_awesome,
                                  size: 40,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'WonderBox 多模态智能伴听助手',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '全时录音 · TEN VAD 切句 · Jev-Style 判决 · 视界抓拍 · 端侧推理',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    _buildFeatureRow(
                                      theme,
                                      icon: Icons.mic,
                                      title: 'TEN VAD 灵敏切句',
                                      desc: '256采样/16ms极速判决，彻底避免首字吞音',
                                    ),
                                    const Divider(height: 16),
                                    _buildFeatureRow(
                                      theme,
                                      icon: Icons.gavel,
                                      title: 'Jev-Style-0.8B 意图对齐',
                                      desc: '快速判别新短句是否切合上下文，自动过滤闲聊',
                                    ),
                                    const Divider(height: 16),
                                    _buildFeatureRow(
                                      theme,
                                      icon: Icons.camera_alt,
                                      title: '实时现场视界抓拍',
                                      desc: '判决相关时秒级抓拍镜头画面并注入上下文',
                                    ),
                                    const Divider(height: 16),
                                    _buildFeatureRow(
                                      theme,
                                      icon: Icons.memory,
                                      title: 'MiniCPM-V-4.6 端侧推理',
                                      desc: '多模态深度思考，毫秒级打字机流式回复',
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  FilledButton.icon(
                                    icon: const Icon(Icons.mic, size: 18),
                                    label: const Text('开启伴听体验'),
                                    onPressed: () {
                                      ref.read(ambientAssistantProvider.notifier).startAmbientListening();
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: chatState.messages.length,
                        itemBuilder: (context, index) {
                          final message = chatState.messages[index];
                          return MessageBubble(key: ValueKey(message.id), message: message);
                        },
                      ),
              ),
              const StopSpeakingButton(),
              const VadDistanceBar(),
              const CameraConfigBar(),
              ChatInputBox(
                isStreaming: chatState.isStreaming,
                isSpeaking: ttsState.isSpeaking,
                onSend: (text) {
                  ref.read(chatControllerProvider.notifier).sendMessage(text);
                },
                onStop: () {
                  ref.read(ttsControllerProvider.notifier).stop();
                  ref.read(chatControllerProvider.notifier).stopStreaming();
                },
              ),
            ],
          ),
          const CameraPreviewFloating(),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
