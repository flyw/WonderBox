import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonder_box/core/storage/preferences_provider.dart';
import 'package:wonder_box/core/storage/storage_keys.dart';
import 'package:wonder_box/features/chat/data/services/tts_service.dart';
import 'package:wonder_box/features/chat/presentation/controllers/tts_controller.dart';
import 'package:wonder_box/features/voice/data/services/qwen3_tts_model_manager.dart';
import 'package:wonder_box/features/voice/data/services/qwen3_tts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Qwen3-TTS 0.6B Q4 Integration Tests', () {
    test('Qwen3TtsModelManager has correct model file name', () {
      expect(Qwen3TtsModelManager.modelFileName, 'Qwen3-TTS-12Hz-0.6B-CustomVoice.Q4_K_M.gguf');
    });

    test('Qwen3TtsService provides all 4 standard neural voices', () {
      final voices = Qwen3TtsService.presetVoices;
      expect(voices.length, 4);
      final voiceIds = voices.map((v) => v.id).toList();
      expect(voiceIds, containsAll(['vivian', 'serena', 'ryan', 'uncle']));
    });

    test('TtsNotifier defaults to Qwen3-TTS engine and Vivian voice', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(ttsControllerProvider);
      expect(state.engine, TtsEngine.qwen3Tts);
      expect(state.qwen3Voice, 'vivian');
    });

    test('TtsNotifier restores saved Qwen3-TTS preferences from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.ttsEngine: TtsEngine.qwen3Tts.name,
        StorageKeys.qwen3Voice: 'serena',
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(ttsControllerProvider);
      expect(state.engine, TtsEngine.qwen3Tts);
      expect(state.qwen3Voice, 'serena');
    });

    test('TtsNotifier writes updated engine and voice to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(ttsControllerProvider.notifier);

      notifier.setQwen3Voice('ryan');
      expect(prefs.getString(StorageKeys.qwen3Voice), 'ryan');
      expect(container.read(ttsControllerProvider).qwen3Voice, 'ryan');

      notifier.setEngine(TtsEngine.systemApple);
      expect(prefs.getString(StorageKeys.ttsEngine), 'systemApple');
      expect(container.read(ttsControllerProvider).engine, TtsEngine.systemApple);

      notifier.setEngine(TtsEngine.qwen3Tts);
      expect(prefs.getString(StorageKeys.ttsEngine), 'qwen3Tts');
      expect(container.read(ttsControllerProvider).engine, TtsEngine.qwen3Tts);
    });
  });
}
