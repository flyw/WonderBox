import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/ambient_assistant_controller.dart';
import 'vad_tuning_sheet.dart';

/// Interactive VAD Distance Slider Axis positioned directly above the camera/chat bar.
/// Allows real-time tactile adjustment of listening range from close-up (10cm) to room far-field (2.5m+).
class VadDistanceBar extends ConsumerWidget {
  const VadDistanceBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ambientAssistantProvider);
    final notifier = ref.read(ambientAssistantProvider.notifier);
    final theme = Theme.of(context);

    // Only show the live distance axis when ambient listening is enabled/active
    if (!state.isListening) return const SizedBox.shrink();

    final ratio = state.distanceRatio;
    final distanceText = _getDistanceText(ratio);
    final isSufficient = state.isEnergySufficient;
    final isSpeechActive = state.isSpeechActive;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSpeechActive
                ? Icons.graphic_eq_rounded
                : (isSufficient ? Icons.hearing_rounded : Icons.hearing_outlined),
            size: 16,
            color: isSpeechActive
                ? Colors.blue.shade600
                : (isSufficient ? Colors.green.shade600 : theme.colorScheme.primary),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '拾音距离轴',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSufficient ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
              Text(
                distanceText,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSpeechActive
                      ? Colors.blue.shade700
                      : (isSufficient ? Colors.green.shade700 : theme.colorScheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3.5,
                activeTrackColor: theme.colorScheme.primary,
                inactiveTrackColor: theme.colorScheme.surfaceContainerHighest,
                thumbColor: theme.colorScheme.primary,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: ratio,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                onChanged: (val) {
                  notifier.setDistanceRatio(val);
                },
              ),
            ),
          ),
          GestureDetector(
            onTap: () => VadTuningSheet.show(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3), width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune, size: 12, color: theme.colorScheme.primary),
                  const SizedBox(width: 2),
                  Text(
                    '详调',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getDistanceText(double r) {
    if (r < 0.15) return '🎯 贴身 10cm';
    if (r < 0.35) return '🎯 近身 25cm';
    if (r < 0.60) return '🛋️ 桌面 45cm';
    if (r < 0.85) return '🌐 房间 1.2m';
    return '🌐 远场 2.5m';
  }
}
