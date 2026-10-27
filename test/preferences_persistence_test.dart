import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonder_box/core/storage/preferences_provider.dart';
import 'package:wonder_box/core/storage/storage_keys.dart';
import 'package:wonder_box/features/camera/presentation/controllers/camera_controller.dart';
import 'package:wonder_box/features/chat/presentation/controllers/ambient_assistant_controller.dart';
import 'package:wonder_box/features/chat/presentation/controllers/tts_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TTS Settings Persistence Tests', () {
    test('TtsNotifier loads saved values from SharedPreferences on build', () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.ttsVoiceId: 'com.apple.speech.synthesis.voice.custom.siri4',
        StorageKeys.ttsVoiceName: 'Siri (Voice 4) · 美国口音',
        StorageKeys.ttsRate: 0.65,
        StorageKeys.ttsPitch: 1.15,
        StorageKeys.ttsAutoSpeak: false,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(ttsControllerProvider);
      expect(state.selectedVoiceId, 'com.apple.speech.synthesis.voice.custom.siri4');
      expect(state.selectedVoiceName, 'Siri (Voice 4) · 美国口音');
      expect(state.rate, 0.65);
      expect(state.pitch, 1.15);
      expect(state.isAutoSpeakEnabled, false);
    });

    test('TtsNotifier writes updated values to SharedPreferences on user interaction', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(ttsControllerProvider.notifier);

      notifier.selectVoice('voice-test-id', 'Voice Test Name');
      expect(prefs.getString(StorageKeys.ttsVoiceId), 'voice-test-id');
      expect(prefs.getString(StorageKeys.ttsVoiceName), 'Voice Test Name');

      notifier.setRate(0.7);
      expect(prefs.getDouble(StorageKeys.ttsRate), 0.7);

      notifier.setPitch(1.2);
      expect(prefs.getDouble(StorageKeys.ttsPitch), 1.2);

      notifier.toggleAutoSpeak();
      expect(prefs.getBool(StorageKeys.ttsAutoSpeak), false);
    });
  });

  group('VAD Distance & Acoustics Persistence Tests', () {
    test('AmbientAssistantNotifier loads saved distance and VAD thresholds on build', () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.vadDistanceRatio: 0.85,
        StorageKeys.vadMinRms: 0.003,
        StorageKeys.vadThreshold: 0.35,
        StorageKeys.vadMinSpeech: 0.12,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(ambientAssistantProvider);
      expect(state.distanceRatio, 0.85);
      expect(state.minRmsThreshold, 0.003);
      expect(state.vadThreshold, 0.35);
      expect(state.minSpeechDuration, 0.12);
    });

    test('AmbientAssistantNotifier persists distance ratio changes when slider moved', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(ambientAssistantProvider.notifier);
      notifier.setDistanceRatio(0.10);

      expect(prefs.getDouble(StorageKeys.vadDistanceRatio), 0.10);
      expect(prefs.getDouble(StorageKeys.vadMinRms), isNotNull);
      expect(prefs.getDouble(StorageKeys.vadThreshold), isNotNull);
      expect(prefs.getDouble(StorageKeys.vadMinSpeech), isNotNull);

      // Verify state reflects changes
      final state = container.read(ambientAssistantProvider);
      expect(state.distanceRatio, 0.10);
    });

    test('AmbientAssistantNotifier persists updateVadConfig changes', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(ambientAssistantProvider.notifier);
      notifier.updateVadConfig(
        vadThreshold: 0.42,
        minRmsThreshold: 0.015,
        minSpeechDuration: 0.22,
        distanceRatio: 0.30,
      );

      expect(prefs.getDouble(StorageKeys.vadThreshold), 0.42);
      expect(prefs.getDouble(StorageKeys.vadMinRms), 0.015);
      expect(prefs.getDouble(StorageKeys.vadMinSpeech), 0.22);
      expect(prefs.getDouble(StorageKeys.vadDistanceRatio), 0.30);
    });
  });

  group('Camera Mode Persistence Tests', () {
    test('CameraNotifier loads saved camera mode on build', () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.cameraMode: AppCameraMode.front.name,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(cameraControllerProvider);
      expect(state.mode, AppCameraMode.front);
      expect(state.isCameraEnabled, true);
    });

    test('CameraNotifier loads off mode and sets isCameraEnabled to false', () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.cameraMode: AppCameraMode.off.name,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(cameraControllerProvider);
      expect(state.mode, AppCameraMode.off);
      expect(state.isCameraEnabled, false);
    });
  });
}
