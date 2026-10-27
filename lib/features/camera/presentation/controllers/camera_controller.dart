import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/storage/preferences_provider.dart';
import '../../../../core/storage/storage_keys.dart';
import '../../data/services/camera_service.dart';

export '../../data/services/camera_service.dart' show AppCameraMode;

class CameraState {
  final AppCameraMode mode;
  final bool isCameraEnabled;
  final bool isInitialized;
  final bool isPreviewVisible;
  final CameraDescription? currentCamera;
  final String? lastCapturedImagePath;
  final String statusMessage;
  final String? errorMessage;

  const CameraState({
    this.mode = AppCameraMode.backUltraWide,
    this.isCameraEnabled = true,
    this.isInitialized = false,
    this.isPreviewVisible = false,
    this.currentCamera,
    this.lastCapturedImagePath,
    this.statusMessage = '摄像头待命',
    this.errorMessage,
  });

  CameraState copyWith({
    AppCameraMode? mode,
    bool? isCameraEnabled,
    bool? isInitialized,
    bool? isPreviewVisible,
    CameraDescription? currentCamera,
    String? lastCapturedImagePath,
    String? statusMessage,
    String? errorMessage,
  }) {
    return CameraState(
      mode: mode ?? this.mode,
      isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
      isInitialized: isInitialized ?? this.isInitialized,
      isPreviewVisible: isPreviewVisible ?? this.isPreviewVisible,
      currentCamera: currentCamera ?? this.currentCamera,
      lastCapturedImagePath: lastCapturedImagePath ?? this.lastCapturedImagePath,
      statusMessage: statusMessage ?? this.statusMessage,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class CameraNotifier extends Notifier<CameraState> {
  late final SharedPreferences _prefs;

  @override
  CameraState build() {
    final service = ref.read(cameraServiceProvider);
    _prefs = ref.watch(sharedPreferencesProvider);

    final savedModeString = _prefs.getString(StorageKeys.cameraMode);
    AppCameraMode initialMode = AppCameraMode.backUltraWide;
    if (savedModeString != null) {
      initialMode = AppCameraMode.values.firstWhere(
        (m) => m.name == savedModeString,
        orElse: () => AppCameraMode.backUltraWide,
      );
    }

    return CameraState(
      mode: initialMode,
      isCameraEnabled: initialMode != AppCameraMode.off,
      isInitialized: service.isInitialized,
      currentCamera: service.currentMobileCamera,
    );
  }

  Future<void> initialize([AppCameraMode? defaultMode]) async {
    final service = ref.read(cameraServiceProvider);
    final targetMode = defaultMode ?? state.mode;
    state = state.copyWith(statusMessage: _getSwitchingStatusForMode(targetMode));
    final success = await service.setCameraMode(targetMode);
    if (success) {
      _prefs.setString(StorageKeys.cameraMode, targetMode.name);
      state = state.copyWith(
        mode: targetMode,
        isCameraEnabled: targetMode != AppCameraMode.off,
        isInitialized: targetMode != AppCameraMode.off,
        currentCamera: service.currentMobileCamera,
        statusMessage: _getStatusForMode(targetMode),
        errorMessage: null,
      );
    } else {
      state = state.copyWith(
        isInitialized: false,
        statusMessage: '未检测到可用摄像头或权限未授予',
      );
    }
  }

  Future<void> setCameraMode(AppCameraMode newMode) async {
    if (state.mode == newMode && (newMode == AppCameraMode.off || state.isInitialized)) {
      return;
    }

    final service = ref.read(cameraServiceProvider);
    state = state.copyWith(
      mode: newMode,
      statusMessage: _getSwitchingStatusForMode(newMode),
    );

    final success = await service.setCameraMode(newMode);
    if (success) {
      _prefs.setString(StorageKeys.cameraMode, newMode.name);
      state = state.copyWith(
        mode: newMode,
        isCameraEnabled: newMode != AppCameraMode.off,
        isInitialized: newMode != AppCameraMode.off,
        currentCamera: service.currentMobileCamera,
        statusMessage: _getStatusForMode(newMode),
        errorMessage: null,
      );
    } else {
      state = state.copyWith(
        statusMessage: '摄像头切换失败',
        errorMessage: '无法切换到所选模式',
      );
    }
  }

  void toggleCameraEnabled() {
    if (state.mode == AppCameraMode.off) {
      setCameraMode(AppCameraMode.backUltraWide);
    } else {
      setCameraMode(AppCameraMode.off);
    }
  }

  void togglePreviewVisible() {
    state = state.copyWith(isPreviewVisible: !state.isPreviewVisible);
  }

  Future<String?> captureFrame() async {
    if (state.mode == AppCameraMode.off || !state.isCameraEnabled) {
      return null;
    }

    final service = ref.read(cameraServiceProvider);
    state = state.copyWith(statusMessage: '📸 正在读取画面...');
    final path = await service.captureFrame();
    if (path != null) {
      state = state.copyWith(
        lastCapturedImagePath: path,
        statusMessage: '✅ 画面读取成功，已融入会话分析',
      );
    } else {
      state = state.copyWith(
        statusMessage: '画面读取跳过或未启用',
      );
    }
    return path;
  }

  String _getStatusForMode(AppCameraMode mode) {
    switch (mode) {
      case AppCameraMode.off:
        return '摄像头已关闭 (仅录音伴听)';
      case AppCameraMode.front:
        return '前置摄像头就绪';
      case AppCameraMode.backUltraWide:
        return '后置超广角摄像头就绪 (0.5x 全景)';
    }
  }

  String _getSwitchingStatusForMode(AppCameraMode mode) {
    switch (mode) {
      case AppCameraMode.off:
        return '正在关闭摄像头...';
      case AppCameraMode.front:
        return '正在切换至前置摄像头...';
      case AppCameraMode.backUltraWide:
        return '正在切换至后置超广角摄像头...';
    }
  }
}

final cameraControllerProvider =
    NotifierProvider<CameraNotifier, CameraState>(CameraNotifier.new);
