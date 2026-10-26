import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final cameraServiceProvider = Provider<CameraService>((ref) {
  final service = CameraService();
  ref.onDispose(() {
    service.disposeCamera();
  });
  return service;
});

class CameraDeviceDescription {
  final String id;
  final String name;
  final bool isFront;

  const CameraDeviceDescription({
    required this.id,
    required this.name,
    this.isFront = false,
  });
}

class CameraService {
  static const MethodChannel _macChannel =
      MethodChannel('com.moefunny.wonder_box/camera');

  CameraController? _mobileController;
  List<CameraDescription> _mobileCameras = [];
  List<CameraDeviceDescription> _macCameras = [];
  CameraDeviceDescription? _activeMacCamera;
  bool _isMacInitialized = false;
  bool _isInitializing = false;
  bool _isEnabled = true; // Auto-capture when Jev decides YES

  CameraController? get controller => _mobileController;
  bool get isInitialized => Platform.isMacOS
      ? _isMacInitialized
      : (_mobileController != null && _mobileController!.value.isInitialized);
  bool get isEnabled => _isEnabled;
  List<CameraDescription> get mobileCameras => _mobileCameras;
  List<CameraDeviceDescription> get macCameras => _macCameras;
  CameraDeviceDescription? get activeMacCamera => _activeMacCamera;

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  /// Initializes the camera (native AVFoundation on macOS, camera plugin on mobile)
  Future<bool> initializeCamera([dynamic preferredCamera]) async {
    if (isInitialized) return true;
    if (_isInitializing) return false;

    _isInitializing = true;
    try {
      if (Platform.isMacOS) {
        return await _initializeMacOS(preferredCamera as String?);
      } else {
        return await _initializeMobile(preferredCamera as CameraDescription?);
      }
    } catch (e) {
      debugPrint('[CameraService] Camera initialization error: $e');
      _isInitializing = false;
      return false;
    }
  }

  Future<bool> _initializeMacOS([String? targetCameraId]) async {
    try {
      final granted =
          await _macChannel.invokeMethod<bool>('requestPermission') ?? false;
      if (!granted) {
        debugPrint('[CameraService] macOS camera permission denied');
        _isInitializing = false;
        return false;
      }

      final rawList = await _macChannel
          .invokeListMethod<Map<dynamic, dynamic>>('getAvailableCameras');
      _macCameras = rawList?.map((map) {
            return CameraDeviceDescription(
              id: map['id'] as String? ?? '',
              name: map['name'] as String? ?? 'macOS Camera',
              isFront: map['isFront'] as bool? ?? true,
            );
          }).toList() ??
          [];

      if (_macCameras.isEmpty) {
        debugPrint('[CameraService] No video capture devices found on macOS');
        _isInitializing = false;
        return false;
      }

      _activeMacCamera = targetCameraId != null
          ? _macCameras.firstWhere(
              (c) => c.id == targetCameraId,
              orElse: () => _macCameras.first,
            )
          : _macCameras.firstWhere(
              (c) => c.isFront,
              orElse: () => _macCameras.first,
            );

      final ok = await _macChannel.invokeMethod<bool>('initializeCamera', {
            'cameraId': _activeMacCamera?.id,
          }) ??
          false;

      _isMacInitialized = ok;
      _isInitializing = false;
      debugPrint(
          '[CameraService] macOS Native AVFoundation camera ready: ${_activeMacCamera?.name}');
      return ok;
    } catch (e) {
      debugPrint('[CameraService] macOS camera setup error: $e');
      _isMacInitialized = false;
      _isInitializing = false;
      return false;
    }
  }

  Future<bool> _initializeMobile([CameraDescription? preferredCamera]) async {
    try {
      _mobileCameras = await availableCameras();
      if (_mobileCameras.isEmpty) {
        debugPrint('[CameraService] No cameras found on mobile device');
        _isInitializing = false;
        return false;
      }

      final camera = preferredCamera ??
          _mobileCameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
            orElse: () => _mobileCameras.first,
          );

      _mobileController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _mobileController!.initialize();
      debugPrint('[CameraService] Mobile Camera initialized: ${camera.name}');
      _isInitializing = false;
      return true;
    } catch (e) {
      debugPrint('[CameraService] Mobile Camera init failed: $e');
      _mobileController = null;
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

    final appDocDir = await getApplicationDocumentsDirectory();
    final capturesDir = Directory('${appDocDir.path}/captures');
    if (!await capturesDir.exists()) {
      await capturesDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final savedPath = '${capturesDir.path}/snapshot_$timestamp.jpg';

    if (Platform.isMacOS) {
      try {
        final path = await _macChannel.invokeMethod<String>('captureFrame', {
          'outputPath': savedPath,
        });
        debugPrint('[CameraService] Frame snapshot saved via AVFoundation: $path');
        return path;
      } catch (e) {
        debugPrint('[CameraService] macOS native capture error: $e');
        return null;
      }
    } else {
      if (_mobileController == null || !_mobileController!.value.isInitialized) {
        return null;
      }
      try {
        final XFile picture = await _mobileController!.takePicture();
        await File(picture.path).copy(savedPath);
        debugPrint('[CameraService] Mobile Frame snapshot saved to: $savedPath');
        return savedPath;
      } catch (e) {
        debugPrint('[CameraService] Mobile capture error: $e');
        return null;
      }
    }
  }

  /// Disposes camera controller
  Future<void> disposeCamera() async {
    try {
      if (Platform.isMacOS) {
        await _macChannel.invokeMethod('disposeCamera');
        _isMacInitialized = false;
      } else {
        await _mobileController?.dispose();
        _mobileController = null;
      }
    } catch (_) {}
  }
}
