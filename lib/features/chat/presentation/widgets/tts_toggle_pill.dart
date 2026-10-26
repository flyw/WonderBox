import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/tts_controller.dart';
import 'tts_voice_sheet.dart';

class TtsTogglePill extends ConsumerWidget {
  const TtsTogglePill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ttsState = ref.watch(ttsControllerProvider);
    final isAuto = ttsState.isAutoSpeakEnabled;
    final isSpeaking = ttsState.isSpeaking;

    final voiceName = ttsState.selectedVoiceName ?? 'Siri';
    final shortName = voiceName.contains('Siri')
        ? 'Siri'
        : (voiceName.length > 4 ? voiceName.substring(0, 4) : voiceName);

    return GestureDetector(
      onLongPress: () => TtsVoiceSheet.show(context),
      child: ActionChip(
        avatar: Icon(
          isSpeaking
              ? Icons.volume_up
              : (isAuto ? Icons.record_voice_over : Icons.voice_over_off),
          size: 14,
          color: isSpeaking
              ? Colors.orangeAccent
              : (isAuto ? Colors.green.shade400 : Colors.grey),
        ),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isSpeaking
                  ? '播报中'
                  : (isAuto ? '$shortName开' : '静音'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isSpeaking
                    ? Colors.orangeAccent
                    : (isAuto ? Colors.green.shade400 : Colors.grey),
              ),
            ),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: () => TtsVoiceSheet.show(context),
              child: Icon(
                Icons.tune,
                size: 12,
                color: isAuto ? Colors.green.shade400 : Colors.grey,
              ),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        visualDensity: VisualDensity.compact,
        side: BorderSide(
          color: isSpeaking
              ? Colors.orangeAccent.withValues(alpha: 0.5)
              : (isAuto ? Colors.green.withValues(alpha: 0.4) : Colors.grey.withValues(alpha: 0.3)),
        ),
        backgroundColor: isSpeaking
            ? Colors.orangeAccent.withValues(alpha: 0.15)
            : (isAuto ? Colors.green.withValues(alpha: 0.12) : Colors.grey.withValues(alpha: 0.08)),
        onPressed: () {
          ref.read(ttsControllerProvider.notifier).toggleAutoSpeak();
        },
      ),
    );
  }
}
