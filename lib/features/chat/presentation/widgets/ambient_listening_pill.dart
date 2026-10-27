import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/ambient_assistant_controller.dart';
import 'vad_tuning_sheet.dart';

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
      message: isListening ? '伴听模式运行中 (点击暂停，长按调优拾音距离)' : '点击启动 TEN VAD 自动伴听分析',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          notifier.toggleAmbientListening();
        },
        onLongPress: () {
          VadTuningSheet.show(context);
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
              if (isListening) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => VadTuningSheet.show(context),
                  child: Icon(Icons.tune, size: 12, color: foregroundColor.withValues(alpha: 0.7)),
                ),
              ],
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
    final isListening = state.isListening;

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
    } else if (isListening) {
      bgColor = theme.colorScheme.surfaceContainer;
      textColor = theme.colorScheme.onSurface;
      iconData = Icons.hearing_rounded;
    } else {
      bgColor = theme.colorScheme.surfaceContainerLow;
      textColor = theme.colorScheme.outline;
      iconData = Icons.info_outline;
    }

    String displayText;
    if (isError) {
      displayText = state.errorMessage!;
    } else if (isSpeaking) {
      displayText = '🎙️ 正在输入: "${state.liveText}"';
    } else if (isListening) {
      final rmsText = 'RMS ${state.currentRms.toStringAsFixed(3)}/${state.minRmsThreshold.toStringAsFixed(3)}';
      final vadText = 'VAD ${(state.vadThreshold * 100).toInt()}%';
      displayText = '${state.statusMessage} · [$rmsText | $vadText]';
    } else {
      displayText = '💡 伴听模式已暂停 (点击右上角 [伴听模式] 胶囊可开启)';
    }

    return InkWell(
      onTap: () => VadTuningSheet.show(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        color: bgColor,
        child: Row(
          children: [
            Icon(iconData, size: 15, color: textColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                displayText,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSpeaking ? FontWeight.bold : FontWeight.normal,
                  color: textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune, size: 11, color: textColor),
                  const SizedBox(width: 2),
                  Text(
                    '调优',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
