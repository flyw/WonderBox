import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/camera_service.dart';

class CameraState {
  final bool isCameraEnabled;
  final bool isInitialized;
  final bool isPreviewVisible;
  final CameraDescription? currentCamera;
  final String? lastCapturedImagePath;
  final String statusMessage;
  final String? errorMessage;

  const CameraState({
    this.isCameraEnabled = true,
    this.isInitialized = false,
    this.isPreviewVisible = false,
    this.currentCamera,
    this.lastCapturedImagePath,
    this.statusMessage = '摄像头待命',
    this.errorMessage,
  });

  CameraState copyWith({
    bool? isCameraEnabled,
    bool? isInitialized,
    bool? isPreviewVisible,
    CameraDescription? currentCamera,
    String? lastCapturedImagePath,
    String? statusMessage,
    String? errorMessage,
  }) {
    return CameraState(
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
  @override
  CameraState build() {
    final service = ref.read(cameraServiceProvider);
    return CameraState(
      isCameraEnabled: service.isEnabled,
      isInitialized: service.isInitialized,
    );
  }

  Future<void> initialize() async {
    final service = ref.read(cameraServiceProvider);
    state = state.copyWith(statusMessage: '正在启动摄像头...');
    final success = await service.initializeCamera();
    if (success) {
      state = state.copyWith(
        isInitialized: true,
        statusMessage: '摄像头就绪 (Jev判决时自动抓拍)',
        errorMessage: null,
      );
    } else {
      state = state.copyWith(
        isInitialized: false,
        statusMessage: '未检测到可用摄像头或权限未授予',
      );
    }
  }

  void toggleCameraEnabled() {
    final service = ref.read(cameraServiceProvider);
    final next = !state.isCameraEnabled;
    service.setEnabled(next);
    state = state.copyWith(
      isCameraEnabled: next,
      statusMessage: next ? '摄像头伴听已启用' : '摄像头已静音(仅录音)',
    );
  }

  void togglePreviewVisible() {
    state = state.copyWith(isPreviewVisible: !state.isPreviewVisible);
  }

  Future<String?> captureFrame() async {
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
}

final cameraControllerProvider =
    NotifierProvider<CameraNotifier, CameraState>(CameraNotifier.new);
