#!/usr/bin/env bash
set -euxo pipefail

mkdir -p build/screenshots
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/emulator_flow_test.dart \
  -d emulator-5554 \
  --dart-define=JRI_EXPORT_TTS_WAV=true \
  > build/screenshots/flutter-run.log 2>&1

WAV_PATH="cache/just_read_it_voice_sample.wav"
adb exec-out run-as com.example.just_read_it cat "$WAV_PATH" > build/screenshots/voice_sample_from_emulator.wav
python3 ../tools/validate_wav.py build/screenshots/voice_sample_from_emulator.wav

test -s build/screenshots/01_txt_import_editor.png
test -s build/screenshots/02_player_playback.png
test -s build/screenshots/voice_sample_from_emulator.wav
python3 ../tools/validate_pngs.py \
  build/screenshots/01_txt_import_editor.png \
  build/screenshots/02_player_playback.png
