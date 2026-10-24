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
              content: Text('🎉 Qwen3-ASR 离线语音模型已就绪！点击输入框旁的麦克风即可开始说话。'),
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
            isReady ? Icons.check_circle : Icons.download,
            color: isReady ? Colors.green : theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(isReady ? '模型已就绪' : 'Qwen3-ASR 本地模型'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isReady)
            const Text(
              'Qwen3-ASR 0.6B 本地离线模型已下载并初始化成功！\n\n'
              '现在您可以直接点击底部麦克风进行语音输入，支持普通话、方言与中英双语识别。',
              style: TextStyle(fontSize: 14, height: 1.4),
            )
          else ...[
            const Text(
              'Qwen3-ASR 0.6B 是高精度的本地端侧语音识别模型（支持30+多语言及22种中国方言）。\n\n'
              '首次使用需下载离线量化模型（约 900MB，仅下载一次，后续完全离线无需流量）。',
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
