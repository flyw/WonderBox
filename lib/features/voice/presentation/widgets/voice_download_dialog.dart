import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/voice_input_controller.dart';

class VoiceDownloadDialog extends ConsumerWidget {
  const VoiceDownloadDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceInputControllerProvider);
    final isDownloading = state.status == VoiceInputStatus.downloading;
    final isReady = state.status == VoiceInputStatus.ready;
    final theme = Theme.of(context);

    // Auto close dialog when download & init completes
    ref.listen(voiceInputControllerProvider, (prev, next) {
      if (prev?.status == VoiceInputStatus.downloading &&
          next.status == VoiceInputStatus.ready) {
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 Streaming-Paraformer 实时流式模型已就绪！点击麦克风即可体验边说边出字。'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    });

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isReady ? Icons.check_circle : Icons.electric_bolt,
            color: isReady ? Colors.green : theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(isReady ? '实时模型已就绪' : 'Streaming-Paraformer 实时模型'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isReady)
            const Text(
              'Streaming-Paraformer 实时打字机模型已就绪！\n\n'
              '现在您可以直接点击底部麦克风说话，输入框将随您的声音实时毫秒级逐字打出。',
              style: TextStyle(fontSize: 14, height: 1.4),
            )
          else ...[
            const Text(
              'Streaming-Paraformer 是专为“边说边出字”设计的低延迟流式语音识别模型。\n\n'
              '量化后仅需约 220MB（相比大模型体积缩小 4 倍，解码延迟仅 20ms）。首次使用需下载一次，后续完全离线运行。',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            if (isDownloading) ...[
              LinearProgressIndicator(
                value: state.downloadProgress > 0 ? state.downloadProgress : null,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      state.statusMessage,
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${(state.downloadProgress * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
            if (state.status == VoiceInputStatus.error && state.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  state.errorMessage!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                ),
              ),
          ],
        ],
      ),
      actions: [
        if (isReady)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('开始使用'),
          )
        else if (!isDownloading) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后再说'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.cloud_download),
            label: const Text('立即下载'),
            onPressed: () {
              ref.read(voiceInputControllerProvider.notifier).downloadModel();
            },
          ),
        ] else
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('后台下载 (关闭窗口)'),
          ),
      ],
    );
  }
}
