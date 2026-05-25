#!/usr/bin/env bash
set -euxo pipefail

mkdir -p build/screenshots
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/emulator_flow_test.dart \
  -d emulator-5554 \
  --dart-define=JRI_EXPORT_TTS_WAV=true \
  --dart-define=JRI_ENABLE_IMPORT_PATH_DIALOG=true \
  > build/screenshots/flutter-run.log 2>&1

flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/emulator_long_markdown_flow_test.dart \
  -d emulator-5554 \
  --dart-define=JRI_EXPORT_TTS_WAV=true \
  --dart-define=JRI_DEFAULT_VOICE_ID=android-system \
  --dart-define=JRI_ENABLE_IMPORT_PATH_DIALOG=true \
  >> build/screenshots/flutter-run.log 2>&1

if ! grep -q "JRI_LONG_DOC_FULL_TEXT_PLAYBACK_VALIDATED" build/screenshots/flutter-run.log; then
  echo "Full long markdown playback was not validated" >&2
  exit 1
fi
if ! grep -q "JRI_LONG_DOC_PLAYBACK_STARTED_AFTER_MS" build/screenshots/flutter-run.log; then
  echo "Long document playback-start latency was not measured" >&2
  exit 1
fi

if grep -Eq "Unable to bind to AudioService|PlatformException|MissingPluginException" build/screenshots/flutter-run.log; then
  echo "Native audio playback error detected in emulator log" >&2
  grep -En "Unable to bind to AudioService|PlatformException|MissingPluginException" build/screenshots/flutter-run.log >&2
  exit 1
fi

if ! grep -Eq "JRI_PLAYBACK_STARTED|JRI_PLAYBACK_COMPLETED" build/screenshots/flutter-run.log; then
  echo "Native media player never proved playback progress" >&2
  exit 1
fi
if ! grep -q "JRI_PLAYBACK_WAV_READY" build/screenshots/flutter-run.log; then
  echo "Playback-sourced WAV was not exported after native playback" >&2
  exit 1
fi

if ! grep -q '^RIFF' build/screenshots/voice_sample_from_emulator.wav; then
  echo "Integration driver did not export playback-sourced WAV" >&2
  cat build/screenshots/voice_sample_from_emulator.wav >&2 || true
  exit 1
fi
python3 ../tools/validate_wav.py build/screenshots/voice_sample_from_emulator.wav
test -s build/screenshots/long_markdown_playback_sample_from_emulator.wav
python3 ../tools/validate_wav.py build/screenshots/long_markdown_playback_sample_from_emulator.wav
python3 -m pip install --user vosk==0.3.45
MODEL_DIR="build/screenshots/vosk-model-small-en-us-0.15"
if [ ! -d "$MODEL_DIR" ]; then
  curl -L --retry 3 -o build/screenshots/vosk-model.zip \
    https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip
  python3 - <<'PY'
import zipfile
from pathlib import Path
zip_path = Path('build/screenshots/vosk-model.zip')
with zipfile.ZipFile(zip_path) as zf:
    zf.extractall('build/screenshots')
PY
fi
python3 ../tools/validate_wav_stt.py \
  build/screenshots/voice_sample_from_emulator.wav \
  --model "$MODEL_DIR" \
  --expected "Simple book speech fixture This simple book is a clear test of imported speech Just Read It should restore the document and read every sentence aloud"
rm -rf "$MODEL_DIR" build/screenshots/vosk-model.zip

test -s build/screenshots/01_txt_import_editor.png
test -s build/screenshots/02_player_playback.png
test -s build/screenshots/voice_sample_from_emulator.wav
test -s build/screenshots/long_markdown_playback_sample_from_emulator.wav
python3 ../tools/validate_pngs.py \
  build/screenshots/01_txt_import_editor.png \
  build/screenshots/02_player_playback.png
