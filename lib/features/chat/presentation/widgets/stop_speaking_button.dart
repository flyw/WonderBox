import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/chat_controller.dart';
import '../controllers/tts_controller.dart';

/// Prominent "停止说话" button shown whenever the assistant is speaking
/// via TTS or actively streaming text. Tapping stops speech and allows
/// ambient listening to resume immediately.
class StopSpeakingButton extends ConsumerWidget {
  const StopSpeakingButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ttsState = ref.watch(ttsControllerProvider);
    final chatState = ref.watch(chatControllerProvider);

    final isSpeaking = ttsState.isSpeaking;
    final isStreaming = chatState.isStreaming;

    if (!isSpeaking && !isStreaming) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(24),
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              ref.read(ttsControllerProvider.notifier).stop();
              ref.read(chatControllerProvider.notifier).stopStreaming();
            },
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: theme.colorScheme.error.withValues(alpha: 0.6),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.error.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.stop_circle_rounded,
                    size: 20,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isSpeaking ? '停止说话' : '停止回答',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(停止后继续听)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onErrorContainer.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
