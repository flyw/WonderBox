import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/camera_controller.dart';

/// Camera selection bar positioned directly above the chat input box.
/// Provides direct one-tap switching between:
/// 1. 关闭 (Camera Off - audio-only mode, saves battery and privacy)
/// 2. 前置 (Front Camera)
/// 3. 后置广角 (Back Camera with maximum ultra-wide angle 0.5x)
class CameraConfigBar extends ConsumerWidget {
  const CameraConfigBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraState = ref.watch(cameraControllerProvider);
    final notifier = ref.read(cameraControllerProvider.notifier);
    final theme = Theme.of(context);
    final currentMode = cameraState.mode;
    final isOff = currentMode == AppCameraMode.off;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
            width: 0.8,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Camera Mode Selector Buttons [ 关闭 | 前置 | 后置广角 ]
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildQuickPill(
                    context,
                    label: '关闭',
                    icon: Icons.videocam_off_rounded,
                    isSelected: currentMode == AppCameraMode.off,
                    onTap: () => notifier.setCameraMode(AppCameraMode.off),
                  ),
                  const SizedBox(width: 4),
                  _buildQuickPill(
                    context,
                    label: '前置',
                    icon: Icons.camera_front_rounded,
                    isSelected: currentMode == AppCameraMode.front,
                    onTap: () => notifier.setCameraMode(AppCameraMode.front),
                  ),
                  const SizedBox(width: 4),
                  _buildQuickPill(
                    context,
                    label: '后置广角',
                    icon: Icons.zoom_out_map_rounded,
                    isSelected: currentMode == AppCameraMode.backUltraWide,
                    onTap: () => notifier.setCameraMode(AppCameraMode.backUltraWide),
                  ),
                ],
              ),
            ),

            if (!isOff) ...[
              const SizedBox(width: 10),
              // Floating PIP preview toggle button
              InkWell(
                onTap: () => notifier.togglePreviewVisible(),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: cameraState.isPreviewVisible
                        ? theme.colorScheme.secondaryContainer
                        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: cameraState.isPreviewVisible
                          ? theme.colorScheme.secondary
                          : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        cameraState.isPreviewVisible
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        size: 16,
                        color: cameraState.isPreviewVisible
                            ? theme.colorScheme.secondary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '浮窗',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cameraState.isPreviewVisible
                              ? theme.colorScheme.onSecondaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickPill(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
