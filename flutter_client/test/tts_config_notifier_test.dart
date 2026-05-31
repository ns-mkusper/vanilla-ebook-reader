import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_read_it/services/model_repository.dart';
import 'package:just_read_it/services/tts_preferences_repository.dart';
import 'package:just_read_it/services/tts_service.dart';

void main() {
  late Directory tempDir;
  late TtsPreferencesRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('just_read_it_tts_config_');
    repository = TtsPreferencesRepository(directory: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('persists speed and pitch independently for each voice', () async {
    final firstSession = TtsConfigNotifier(repository);
    await firstSession.loadPreferences();

    firstSession.updateRate(1.5);
    firstSession.updatePitch(1.2);
    firstSession.selectVoice(
      const VoiceSelection(
        id: 'android-system',
        displayName: 'Android Default Voice',
        backend: TtsEngineBackend.androidSystem,
      ),
    );
    expect(firstSession.state.rate, 1.0);
    expect(firstSession.state.pitch, 1.0);

    firstSession.updateRate(0.75);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final secondSession = TtsConfigNotifier(repository);
    await secondSession.loadPreferences();
    expect(secondSession.state.voice.id, 'flite-classic');
    expect(secondSession.state.rate, 1.5);
    expect(secondSession.state.pitch, 1.2);

    secondSession.selectVoice(
      const VoiceSelection(
        id: 'android-system',
        displayName: 'Android Default Voice',
        backend: TtsEngineBackend.androidSystem,
      ),
    );
    expect(secondSession.state.rate, 0.75);
    expect(secondSession.state.pitch, 1.0);
  });
}
