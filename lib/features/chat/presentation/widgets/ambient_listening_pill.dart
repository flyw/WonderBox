import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/ambient_assistant_controller.dart';

class AmbientListeningPill extends ConsumerWidget {
  const AmbientListeningPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ambientAssistantProvider);
    final notifier = ref.read(ambientAssistantProvider.notifier);
    final theme = Theme.of(context);

    final isListening = state.isListening;
    final isSpeechActive = state.isSpeechActive;

    Color backgroundColor;
    Color foregroundColor;
    IconData icon;

    if (isListening) {
      if (isSpeechActive) {
        backgroundColor = theme.colorScheme.primaryContainer;
        foregroundColor = theme.colorScheme.onPrimaryContainer;
        icon = Icons.graphic_eq_rounded;
      } else {
        backgroundColor = Colors.green.withValues(alpha: 0.15);
        foregroundColor = Colors.green.shade700;
        icon = Icons.hearing_rounded;
      }
    } else {
      backgroundColor = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
      foregroundColor = theme.colorScheme.outline;
      icon = Icons.hearing_disabled_rounded;
    }

    return Tooltip(
      message: isListening ? '伴听模式运行中 (点击暂停)' : '点击启动 TEN VAD 自动伴听分析',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          notifier.toggleAmbientListening();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isListening
                  ? (isSpeechActive ? theme.colorScheme.primary : Colors.green.withValues(alpha: 0.4))
                  : theme.colorScheme.outline.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: foregroundColor),
              const SizedBox(width: 6),
              Text(
                isListening
                    ? (isSpeechActive ? '聆听中...' : 'TEN VAD 伴听')
                    : '伴听模式',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: foregroundColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AmbientStatusBar extends ConsumerWidget {
  const AmbientStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ambientAssistantProvider);
    final theme = Theme.of(context);

    final isError = state.errorMessage != null;
    final isRelevant = state.lastDecision == 'relevant';
    final isIgnored = state.lastDecision == 'ignored';
    final isSpeaking = state.liveText.isNotEmpty;

    Color bgColor;
    Color textColor;
    IconData iconData;

    if (isError) {
      bgColor = theme.colorScheme.errorContainer;
      textColor = theme.colorScheme.onErrorContainer;
      iconData = Icons.error_outline_rounded;
    } else if (isSpeaking) {
      bgColor = Colors.blue.withValues(alpha: 0.15);
      textColor = Colors.blue.shade800;
      iconData = Icons.graphic_eq_rounded;
    } else if (isRelevant) {
      bgColor = Colors.green.withValues(alpha: 0.15);
      textColor = Colors.green.shade800;
      iconData = Icons.auto_awesome;
    } else if (isIgnored) {
      bgColor = theme.colorScheme.surfaceContainerHighest;
      textColor = theme.colorScheme.onSurfaceVariant;
      iconData = Icons.filter_alt_outlined;
    } else if (state.isListening) {
      bgColor = theme.colorScheme.surfaceContainer;
      textColor = theme.colorScheme.onSurface;
      iconData = Icons.hearing_rounded;
    } else {
      bgColor = theme.colorScheme.surfaceContainerLow;
      textColor = theme.colorScheme.outline;
      iconData = Icons.info_outline;
    }

    final displayText = isError
        ? state.errorMessage!
        : (isSpeaking
            ? '🎙️ 听到您在说: "${state.liveText}"'
            : (state.isListening
                ? state.statusMessage
                : '💡 伴听模式已暂停 (点击右上角 [伴听模式] 胶囊可开启)'));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      color: bgColor,
      child: Row(
        children: [
          Icon(iconData, size: 15, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              displayText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSpeaking ? FontWeight.bold : FontWeight.normal,
                color: textColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
