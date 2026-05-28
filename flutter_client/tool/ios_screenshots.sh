#!/usr/bin/env bash
set -euxo pipefail

mkdir -p build/screenshots
: > build/screenshots/flutter-run.log

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required for iOS simulator validation" >&2
  exit 1
fi

resolve_simulator() {
  python3 - <<'PY'
import json
import subprocess
import sys

preferred = [
    'iPhone 16',
    'iPhone 15',
    'iPhone 14',
    'iPhone 13',
]
raw = subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j'], text=True)
devices = json.loads(raw).get('devices', {})
flat = []
for runtime, entries in devices.items():
    if 'iOS' not in runtime:
        continue
    for device in entries:
        if not device.get('isAvailable', True):
            continue
        flat.append(device)
for device in flat:
    if device.get('state') == 'Booted':
        print(device['udid'])
        sys.exit(0)
for name in preferred:
    for device in flat:
        if device.get('name') == name:
            print(device['udid'])
            sys.exit(0)
for device in flat:
    if device.get('name', '').startswith('iPhone'):
        print(device['udid'])
        sys.exit(0)
raise SystemExit('No available iPhone simulator found')
PY
}

DEVICE_ID="${IOS_DEVICE_ID:-$(resolve_simulator)}"
xcrun simctl boot "$DEVICE_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE_ID" -b

flutter build ios \
  --simulator \
  --debug \
  --target=integration_test/emulator_flow_test.dart \
  --dart-define=JRI_EXPORT_TTS_WAV=true \
  --dart-define=JRI_ENABLE_IMPORT_PATH_DIALOG=true \
  2>&1 | tee build/screenshots/flutter-run.log

timeout 15m flutter drive \
  --no-build \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/emulator_flow_test.dart \
  -d "$DEVICE_ID" \
  2>&1 | tee -a build/screenshots/flutter-run.log

flutter build ios \
  --simulator \
  --debug \
  --target=integration_test/emulator_long_markdown_flow_test.dart \
  --dart-define=JRI_EXPORT_TTS_WAV=true \
  --dart-define=JRI_DEFAULT_VOICE_ID=flite-classic \
  --dart-define=JRI_EXPECTED_LONG_DOC_VOICE_LABEL='Motorola Male (Flite)' \
  --dart-define=JRI_ENABLE_IMPORT_PATH_DIALOG=true \
  2>&1 | tee -a build/screenshots/flutter-run.log

timeout 20m flutter drive \
  --no-build \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/emulator_long_markdown_flow_test.dart \
  -d "$DEVICE_ID" \
  2>&1 | tee -a build/screenshots/flutter-run.log

if ! grep -q "JRI_LONG_DOC_FULL_TEXT_PLAYBACK_VALIDATED" build/screenshots/flutter-run.log; then
  echo "Full long markdown playback was not validated" >&2
  exit 1
fi
if ! grep -q "JRI_LONG_DOC_PLAYBACK_STARTED_AFTER_MS" build/screenshots/flutter-run.log; then
  echo "Long document playback-start latency was not measured" >&2
  exit 1
fi

if grep -Eiq "Unable to bind to AudioService|PlatformException|MissingPluginException|Failed to lookup symbol|dlopen|Library not loaded|Symbol not found|EXC_BAD_ACCESS|Fatal error|AVAudioSession.*error" build/screenshots/flutter-run.log; then
  echo "Native iOS audio/Rust/plugin error detected in simulator log" >&2
  grep -Ein "Unable to bind to AudioService|PlatformException|MissingPluginException|Failed to lookup symbol|dlopen|Library not loaded|Symbol not found|EXC_BAD_ACCESS|Fatal error|AVAudioSession.*error" build/screenshots/flutter-run.log >&2
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
VENV_DIR="build/screenshots/venv"
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --upgrade pip
"$VENV_DIR/bin/python" -m pip install --only-binary=:all: vosk==0.3.45
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
"$VENV_DIR/bin/python" ../tools/validate_wav_stt.py \
  build/screenshots/voice_sample_from_emulator.wav \
  --model "$MODEL_DIR" \
  --expected "Simple book speech fixture This simple book is a clear test of imported speech Just Read It should restore the document and read every sentence aloud" \
  --min-coverage 0.60
rm -rf "$MODEL_DIR" "$VENV_DIR" build/screenshots/vosk-model.zip

test -s build/screenshots/01_txt_import_editor.png
test -s build/screenshots/02_player_playback.png
test -s build/screenshots/voice_sample_from_emulator.wav
test -s build/screenshots/long_markdown_playback_sample_from_emulator.wav
python3 ../tools/validate_pngs.py \
  build/screenshots/01_txt_import_editor.png \
  build/screenshots/02_player_playback.png

xcrun simctl io "$DEVICE_ID" screenshot build/screenshots/final-ios-simulator.png || true
