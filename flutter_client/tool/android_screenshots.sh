#!/usr/bin/env bash
set -euxo pipefail

mkdir -p build/screenshots
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/emulator_txt_screenshot_test.dart \
  -d emulator-5554 \
  > build/screenshots/flutter-run.log 2>&1

flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/emulator_flow_test.dart \
  -d emulator-5554 \
  --keep-app-running \
  --dart-define=JRI_EXPORT_TTS_WAV=true \
  >> build/screenshots/flutter-run.log 2>&1

if grep -Eq "Unable to bind to AudioService|PlatformException|MissingPluginException" build/screenshots/flutter-run.log; then
  echo "Native audio playback error detected in emulator log" >&2
  grep -En "Unable to bind to AudioService|PlatformException|MissingPluginException" build/screenshots/flutter-run.log >&2
  exit 1
fi

WAV_PATH="cache/just_read_it_voice_sample.wav"
adb exec-out run-as com.example.just_read_it cat "$WAV_PATH" > build/screenshots/voice_sample_from_emulator.wav
if ! grep -q '^RIFF' build/screenshots/voice_sample_from_emulator.wav; then
  echo "Failed to pull exported emulator WAV from app cache" >&2
  cat build/screenshots/voice_sample_from_emulator.wav >&2 || true
  exit 1
fi
python3 ../tools/validate_wav.py build/screenshots/voice_sample_from_emulator.wav

test -s build/screenshots/01_txt_import_editor.png
test -s build/screenshots/02_player_playback.png
test -s build/screenshots/voice_sample_from_emulator.wav
python3 ../tools/validate_pngs.py \
  build/screenshots/01_txt_import_editor.png \
  build/screenshots/02_player_playback.png
