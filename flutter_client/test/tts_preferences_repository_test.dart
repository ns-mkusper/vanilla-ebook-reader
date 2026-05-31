import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_read_it/services/tts_preferences_repository.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('just_read_it_tts_prefs_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('saves and loads playback preferences by voice id', () async {
    final repository = TtsPreferencesRepository(directory: tempDir);

    await repository.savePreference(
      'flite-classic',
      const VoicePlaybackPreference(rate: 1.5, pitch: 1.2),
    );
    await repository.savePreference(
      'android-system',
      const VoicePlaybackPreference(rate: 0.75, pitch: 1.0),
    );

    final reloaded =
        await TtsPreferencesRepository(directory: tempDir).loadPreferences();

    expect(reloaded['flite-classic']?.rate, 1.5);
    expect(reloaded['flite-classic']?.pitch, 1.2);
    expect(reloaded['android-system']?.rate, 0.75);
    expect(reloaded['android-system']?.pitch, 1.0);
  });

  test('clamps stored out-of-range playback preferences', () async {
    final file = File('${tempDir.path}/${TtsPreferencesRepository.fileName}');
    await file.writeAsString('''
{
  "voice": {"rate": 9.0, "pitch": 0.1}
}
''');

    final preferences =
        await TtsPreferencesRepository(directory: tempDir).loadPreferences();

    expect(preferences['voice']?.rate, 3.0);
    expect(preferences['voice']?.pitch, 0.7);
  });
}
