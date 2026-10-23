import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/voice_input_controller.dart';

class VoiceDownloadDialog extends ConsumerWidget {
  const VoiceDownloadDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceInputControllerProvider);
    final isDownloading = state.status == VoiceInputStatus.downloading;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.download, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Qwen3-ASR 本地模型'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
      ),
      actions: [
        if (!isDownloading) ...[
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
