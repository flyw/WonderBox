import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/camera_controller.dart';

class CameraTogglePill extends ConsumerWidget {
  const CameraTogglePill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraState = ref.watch(cameraControllerProvider);
    final theme = Theme.of(context);
    final isEnabled = cameraState.isCameraEnabled;

    return InkWell(
      onTap: () {
        ref.read(cameraControllerProvider.notifier).toggleCameraEnabled();
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isEnabled
              ? theme.colorScheme.secondaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isEnabled
                ? theme.colorScheme.secondary
                : theme.colorScheme.outlineVariant,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isEnabled ? Icons.videocam : Icons.videocam_off,
              size: 15,
              color: isEnabled
                  ? theme.colorScheme.secondary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              isEnabled ? '视界已开' : '视界静音',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isEnabled
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (isEnabled) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () {
                  ref.read(cameraControllerProvider.notifier).togglePreviewVisible();
                },
                child: Icon(
                  cameraState.isPreviewVisible ? Icons.visibility_off : Icons.visibility,
                  size: 14,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
