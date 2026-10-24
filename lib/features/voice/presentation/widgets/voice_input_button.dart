import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/voice_input_controller.dart';
import 'voice_download_dialog.dart';

class VoiceInputButton extends ConsumerWidget {
  final ValueChanged<String> onTextRecognized;
  final VoidCallback? onRecordingStarted;

  const VoiceInputButton({
    super.key,
    required this.onTextRecognized,
    this.onRecordingStarted,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceInputControllerProvider);
    final notifier = ref.read(voiceInputControllerProvider.notifier);
    final theme = Theme.of(context);

    if (state.status == VoiceInputStatus.downloading) {
      return IconButton(
        icon: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: state.downloadProgress > 0 ? state.downloadProgress : null,
          ),
        ),
        tooltip: '实时模型下载中...',
        onPressed: () {
          showDialog(
            context: context,
            builder: (_) => const VoiceDownloadDialog(),
          );
        },
      );
    }

    if (state.status == VoiceInputStatus.recording) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${state.recordingSeconds}s',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.check_circle, color: theme.colorScheme.primary),
            tooltip: '完成录音',
            onPressed: () async {
              await notifier.stopRecording();
            },
          ),
          IconButton(
            icon: Icon(Icons.close, color: theme.colorScheme.error),
            tooltip: '取消录音',
            onPressed: () {
              notifier.cancelRecording();
            },
          ),
        ],
      );
    }

    // Default idle / model missing state
    final isModelMissing = state.status == VoiceInputStatus.modelMissing;

    return IconButton(
      icon: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.mic_none_rounded,
            color: isModelMissing
                ? theme.colorScheme.outline
                : theme.colorScheme.onSurfaceVariant,
          ),
          if (isModelMissing)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_downward,
                  size: 8,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ),
        ],
      ),
      tooltip: isModelMissing ? '下载实时流式模型' : '实时语音输入 (Streaming-Paraformer)',
      onPressed: () async {
        if (isModelMissing) {
          showDialog(
            context: context,
            builder: (_) => const VoiceDownloadDialog(),
          );
        } else {
          onRecordingStarted?.call();
          await notifier.startRecording(
            onLiveText: (text) {
              onTextRecognized(text);
            },
          );
        }
      },
    );
  }
}
