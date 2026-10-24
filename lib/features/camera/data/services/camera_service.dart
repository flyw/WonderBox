import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final cameraServiceProvider = Provider<CameraService>((ref) {
  final service = CameraService();
  ref.onDispose(() {
    service.disposeCamera();
  });
  return service;
});

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _availableCameras = [];
  bool _isInitializing = false;
  bool _isEnabled = true; // Auto-capture when Jev decides YES

  CameraController? get controller => _controller;
  bool get isInitialized => _controller != null && _controller!.value.isInitialized;
  bool get isEnabled => _isEnabled;
  List<CameraDescription> get cameras => _availableCameras;

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  /// Initializes the primary camera
  Future<bool> initializeCamera([CameraDescription? preferredCamera]) async {
    if (isInitialized) return true;
    if (_isInitializing) return false;

    _isInitializing = true;
    try {
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        debugPrint('[CameraService] No cameras found on device');
        _isInitializing = false;
        return false;
      }

      final camera = preferredCamera ??
          _availableCameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
            orElse: () => _availableCameras.first,
          );

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();
      debugPrint('[CameraService] Camera successfully initialized: ${camera.name}');
      _isInitializing = false;
      return true;
    } catch (e) {
      debugPrint('[CameraService] Camera initialization error: $e');
      _controller = null;
      _isInitializing = false;
      return false;
    }
  }

  /// Captures a single image frame and saves it to app documents captures directory
  Future<String?> captureFrame() async {
    if (!_isEnabled) {
      debugPrint('[CameraService] Camera capture is disabled by user');
      return null;
    }

    if (!isInitialized) {
      final success = await initializeCamera();
      if (!success) {
        debugPrint('[CameraService] Camera not available for capture');
        return null;
      }
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return null;
    }

    try {
      final XFile picture = await _controller!.takePicture();

      // Ensure directory exists in app documents
      final appDocDir = await getApplicationDocumentsDirectory();
      final capturesDir = Directory('${appDocDir.path}/captures');
      if (!await capturesDir.exists()) {
        await capturesDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final savedPath = '${capturesDir.path}/snapshot_$timestamp.jpg';
      await File(picture.path).copy(savedPath);

      debugPrint('[CameraService] Frame snapshot saved to: $savedPath');
      return savedPath;
    } catch (e) {
      debugPrint('[CameraService] Capture frame error: $e');
      return null;
    }
  }

  /// Disposes camera controller
  Future<void> disposeCamera() async {
    try {
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
  }
}
