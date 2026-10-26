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

enum AppCameraMode {
  off,
  front,
  backUltraWide,
}

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
  CameraDescription? _currentMobileCamera;
  AppCameraMode _currentMode = AppCameraMode.backUltraWide;
  bool _isMacInitialized = false;
  bool _isInitializing = false;
  bool _isEnabled = true; // Auto-capture when Jev decides YES

  CameraController? get controller => _mobileController;
  bool get isInitialized => Platform.isMacOS
      ? _isMacInitialized
      : (_mobileController != null && _mobileController!.value.isInitialized);
  bool get isEnabled => _isEnabled && _currentMode != AppCameraMode.off;
  AppCameraMode get currentMode => _currentMode;
  List<CameraDescription> get mobileCameras => _mobileCameras;
  CameraDescription? get currentMobileCamera => _currentMobileCamera;
  List<CameraDeviceDescription> get macCameras => _macCameras;
  CameraDeviceDescription? get activeMacCamera => _activeMacCamera;

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  /// Initializes the camera with the currently configured mode
  Future<bool> initializeCamera([dynamic preferredCamera]) async {
    return await setCameraMode(_currentMode);
  }

  /// Sets camera mode: off, front, or backUltraWide
  Future<bool> setCameraMode(AppCameraMode mode) async {
    _currentMode = mode;
    if (mode == AppCameraMode.off) {
      _isEnabled = false;
      await disposeCamera();
      debugPrint('[CameraService] Camera switched to OFF mode');
      return true;
    }

    _isEnabled = true;
    if (_isInitializing) return false;
    _isInitializing = true;

    try {
      if (Platform.isMacOS) {
        final ok = await _switchModeMacOS(mode);
        _isInitializing = false;
        return ok;
      } else {
        final ok = await _switchModeMobile(mode);
        _isInitializing = false;
        return ok;
      }
    } catch (e) {
      debugPrint('[CameraService] Error switching camera mode: $e');
      _isInitializing = false;
      return false;
    }
  }

  Future<bool> _switchModeMacOS(AppCameraMode mode) async {
    try {
      final granted =
          await _macChannel.invokeMethod<bool>('requestPermission') ?? false;
      if (!granted) {
        debugPrint('[CameraService] macOS camera permission denied');
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
        return false;
      }

      if (mode == AppCameraMode.front) {
        _activeMacCamera = _macCameras.firstWhere(
          (c) => c.isFront,
          orElse: () => _macCameras.first,
        );
      } else {
        // Prefer external or back camera if available
        _activeMacCamera = _macCameras.firstWhere(
          (c) => !c.isFront,
          orElse: () => _macCameras.first,
        );
      }

      final ok = await _macChannel.invokeMethod<bool>('initializeCamera', {
            'cameraId': _activeMacCamera?.id,
          }) ??
          false;

      _isMacInitialized = ok;
      debugPrint(
          '[CameraService] macOS Native AVFoundation camera ready: ${_activeMacCamera?.name}');
      return ok;
    } catch (e) {
      debugPrint('[CameraService] macOS camera setup error: $e');
      _isMacInitialized = false;
      return false;
    }
  }

  Future<bool> _switchModeMobile(AppCameraMode mode) async {
    try {
      if (_mobileCameras.isEmpty) {
        _mobileCameras = await availableCameras();
      }
      if (_mobileCameras.isEmpty) {
        debugPrint('[CameraService] No cameras found on mobile device');
        return false;
      }

      CameraDescription targetCamera;
      if (mode == AppCameraMode.front) {
        targetCamera = _mobileCameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => _mobileCameras.first,
        );
      } else {
        // Back ultra-wide mode:
        // Priority 1: back camera with ultraWide lens type
        CameraDescription? ultraWide;
        for (final c in _mobileCameras) {
          if (c.lensDirection == CameraLensDirection.back &&
              c.lensType == CameraLensType.ultraWide) {
            ultraWide = c;
            break;
          }
        }
        // Priority 2: back camera with 'ultra' or '0.5' in name/identifier
        if (ultraWide == null) {
          for (final c in _mobileCameras) {
            if (c.lensDirection == CameraLensDirection.back &&
                (c.name.toLowerCase().contains('ultra') ||
                    c.name.toLowerCase().contains('0.5'))) {
              ultraWide = c;
              break;
            }
          }
        }
        // Priority 3: any back camera
        ultraWide ??= _mobileCameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => _mobileCameras.first,
        );
        targetCamera = ultraWide;
      }

      // Dispose existing controller before creating new one
      if (_mobileController != null) {
        await _mobileController!.dispose();
        _mobileController = null;
      }

      _currentMobileCamera = targetCamera;
      _mobileController = CameraController(
        targetCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _mobileController!.initialize();
      debugPrint(
          '[CameraService] Mobile Camera initialized: ${targetCamera.name} (lens: ${targetCamera.lensDirection}, type: ${targetCamera.lensType})');

      // Crucial: Set flash mode to OFF immediately to prevent screen whitening or flash
      try {
        await _mobileController!.setFlashMode(FlashMode.off);
        debugPrint('[CameraService] Flash mode disabled (FlashMode.off)');
      } catch (e) {
        debugPrint('[CameraService] setFlashMode(FlashMode.off) notice: $e');
      }

      // If back ultra-wide mode, set zoom level to minimum (maximum wide angle)
      if (mode == AppCameraMode.backUltraWide) {
        try {
          final minZoom = await _mobileController!.getMinZoomLevel();
          await _mobileController!.setZoomLevel(minZoom);
          debugPrint(
              '[CameraService] Back ultra-wide zoom level set to min: $minZoom');
        } catch (e) {
          debugPrint('[CameraService] setZoomLevel error (notice): $e');
        }
      }

      return true;
    } catch (e) {
      debugPrint('[CameraService] Mobile Camera switch failed: $e');
      _mobileController = null;
      return false;
    }
  }

  /// Captures a single image frame and saves it to app documents captures directory
  Future<String?> captureFrame() async {
    if (!_isEnabled || _currentMode == AppCameraMode.off) {
      debugPrint('[CameraService] Camera capture is skipped (camera is OFF)');
      return null;
    }

    if (!isInitialized) {
      final success = await setCameraMode(_currentMode);
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
        // Ensure flash remains off before taking picture
        try {
          await _mobileController!.setFlashMode(FlashMode.off);
        } catch (_) {}

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
