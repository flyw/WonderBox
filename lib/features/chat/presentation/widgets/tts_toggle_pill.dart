import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/tts_service.dart';
import '../controllers/tts_controller.dart';
import 'tts_voice_sheet.dart';

class TtsTogglePill extends ConsumerWidget {
  const TtsTogglePill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ttsState = ref.watch(ttsControllerProvider);
    final isAuto = ttsState.isAutoSpeakEnabled;
    final isSpeaking = ttsState.isSpeaking;
    final isQwen3 = ttsState.engine == TtsEngine.qwen3Tts;

    String shortName;
    if (isQwen3) {
      final v = ttsState.qwen3Voice;
      final cap = v.isNotEmpty ? '${v[0].toUpperCase()}${v.substring(1)}' : 'Qwen3';
      shortName = 'Qwen3·$cap';
    } else {
      final voiceName = ttsState.selectedVoiceName ?? 'Siri';
      if (voiceName.contains('Voice 4') || voiceName.contains('声音 4') || (voiceName.contains('Siri') && voiceName.contains('4'))) {
        shortName = 'Siri 4';
      } else if (voiceName.contains('Siri')) {
        shortName = 'Siri';
      } else if (voiceName.length > 4) {
        shortName = voiceName.substring(0, 4);
      } else {
        shortName = voiceName;
      }
    }

    return GestureDetector(
      onLongPress: () => TtsVoiceSheet.show(context),
      child: ActionChip(
        avatar: Icon(
          isSpeaking
              ? Icons.volume_up
              : (isAuto
                  ? (isQwen3 ? Icons.auto_awesome : Icons.record_voice_over)
                  : Icons.voice_over_off),
          size: 14,
          color: isSpeaking
              ? Colors.orangeAccent
              : (isAuto ? (isQwen3 ? Colors.deepPurple.shade300 : Colors.green.shade400) : Colors.grey),
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
                    : (isAuto ? (isQwen3 ? Colors.deepPurple.shade300 : Colors.green.shade400) : Colors.grey),
              ),
            ),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: () => TtsVoiceSheet.show(context),
              child: Icon(
                Icons.tune,
                size: 12,
                color: isAuto ? (isQwen3 ? Colors.deepPurple.shade300 : Colors.green.shade400) : Colors.grey,
              ),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        visualDensity: VisualDensity.compact,
        side: BorderSide(
          color: isSpeaking
              ? Colors.orangeAccent.withValues(alpha: 0.5)
              : (isAuto
                  ? (isQwen3 ? Colors.deepPurple.withValues(alpha: 0.4) : Colors.green.withValues(alpha: 0.4))
                  : Colors.grey.withValues(alpha: 0.3)),
        ),
        backgroundColor: isSpeaking
          ? Colors.orangeAccent.withValues(alpha: 0.15)
          : (isAuto
              ? (isQwen3 ? Colors.deepPurple.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.12))
              : Colors.grey.withValues(alpha: 0.08)),
        onPressed: () {
          ref.read(ttsControllerProvider.notifier).toggleAutoSpeak();
        },
      ),
    );
  }
}
