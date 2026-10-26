import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/camera_controller.dart';

/// Camera configuration bar positioned directly above the chat input box.
/// Allows the user to select between:
/// 1. Back camera with maximum ultra-wide angle (0.5x)
/// 2. Front camera
/// 3. Camera off (disable visual capture, audio-only)
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 0.8,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Dropdown Configuration Button
            PopupMenuButton<AppCameraMode>(
              tooltip: '摄像头配置',
              initialValue: currentMode,
              onSelected: (newMode) {
                notifier.setCameraMode(newMode);
              },
              itemBuilder: (context) => [
                _buildMenuItem(
                  context,
                  mode: AppCameraMode.backUltraWide,
                  isSelected: currentMode == AppCameraMode.backUltraWide,
                  icon: Icons.zoom_out_map_rounded,
                  title: '后置摄像头 (最大超广角)',
                  subtitle: '0.5x 视角，全景捕捉眼前桌面或物体',
                ),
                _buildMenuItem(
                  context,
                  mode: AppCameraMode.front,
                  isSelected: currentMode == AppCameraMode.front,
                  icon: Icons.camera_front_rounded,
                  title: '前置摄像头',
                  subtitle: '自拍视角，适合人脸及面对交流',
                ),
                _buildMenuItem(
                  context,
                  mode: AppCameraMode.off,
                  isSelected: currentMode == AppCameraMode.off,
                  icon: Icons.videocam_off_rounded,
                  title: '关闭摄像头',
                  subtitle: '不读取现场画面，节省电量与隐私保护',
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isOff
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isOff
                        ? theme.colorScheme.outlineVariant
                        : theme.colorScheme.primary.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getModeIcon(currentMode),
                      size: 16,
                      color: isOff
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _getModeLabel(currentMode),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isOff
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: isOff
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Quick 1-tap segment buttons
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildQuickPill(
                    context,
                    label: '关闭',
                    icon: Icons.videocam_off,
                    isSelected: currentMode == AppCameraMode.off,
                    onTap: () => notifier.setCameraMode(AppCameraMode.off),
                  ),
                  _buildQuickPill(
                    context,
                    label: '前置',
                    icon: Icons.camera_front,
                    isSelected: currentMode == AppCameraMode.front,
                    onTap: () => notifier.setCameraMode(AppCameraMode.front),
                  ),
                  _buildQuickPill(
                    context,
                    label: '后置广角',
                    icon: Icons.zoom_out_map,
                    isSelected: currentMode == AppCameraMode.backUltraWide,
                    onTap: () => notifier.setCameraMode(AppCameraMode.backUltraWide),
                  ),
                ],
              ),
            ),

            if (!isOff) ...[
              const SizedBox(width: 8),
              // Floating PIP preview toggle button
              InkWell(
                onTap: () => notifier.togglePreviewVisible(),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: cameraState.isPreviewVisible
                        ? theme.colorScheme.secondaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: cameraState.isPreviewVisible
                          ? theme.colorScheme.secondary
                          : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        cameraState.isPreviewVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                        size: 14,
                        color: cameraState.isPreviewVisible
                            ? theme.colorScheme.secondary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '浮窗',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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

  PopupMenuItem<AppCameraMode> _buildMenuItem(
    BuildContext context, {
    required AppCameraMode mode,
    required bool isSelected,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    return PopupMenuItem<AppCameraMode>(
      value: mode,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (isSelected)
            Icon(Icons.check, size: 18, color: theme.colorScheme.primary),
        ],
      ),
    );
  }

  IconData _getModeIcon(AppCameraMode mode) {
    switch (mode) {
      case AppCameraMode.off:
        return Icons.videocam_off_rounded;
      case AppCameraMode.front:
        return Icons.camera_front_rounded;
      case AppCameraMode.backUltraWide:
        return Icons.zoom_out_map_rounded;
    }
  }

  String _getModeLabel(AppCameraMode mode) {
    switch (mode) {
      case AppCameraMode.off:
        return '摄像头: 已关闭';
      case AppCameraMode.front:
        return '摄像头: 前置';
      case AppCameraMode.backUltraWide:
        return '摄像头: 后置超广角';
    }
  }
}
