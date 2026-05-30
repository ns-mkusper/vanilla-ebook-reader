#!/usr/bin/env bash
set -euxo pipefail

mkdir -p build/screenshots
: > build/screenshots/flutter-run.log

collect_simulator_diagnostics() {
  local reason="$1"
  if [ -z "${DEVICE_ID:-}" ]; then
    return 0
  fi
  echo "Collecting iOS simulator diagnostics after: $reason" >&2
  xcrun simctl io "$DEVICE_ID" screenshot "build/screenshots/ios-diagnostic-${reason}.png" >/dev/null 2>&1 || true
  xcrun simctl spawn "$DEVICE_ID" log show \
    --last 10m \
    --style compact \
    --predicate 'process == "Runner" OR eventMessage CONTAINS "justReadIt" OR eventMessage CONTAINS "Flutter"' \
    > "build/screenshots/ios-simulator-${reason}.log" 2>&1 || true
}

trap 'collect_simulator_diagnostics failure' ERR

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

wait_for_log() {
  local marker="$1"
  local timeout_seconds="$2"
  local deadline=$((SECONDS + timeout_seconds))
  while (( SECONDS < deadline )); do
    if grep -q "$marker" build/screenshots/flutter-run.log; then
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for log marker: $marker" >&2
  tail -200 build/screenshots/flutter-run.log >&2 || true
  return 1
}

wait_for_log_after_line() {
  local marker="$1"
  local timeout_seconds="$2"
  local start_line="$3"
  local deadline=$((SECONDS + timeout_seconds))
  while (( SECONDS < deadline )); do
    if tail -n +"$start_line" build/screenshots/flutter-run.log | grep -q "$marker"; then
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for log marker after line $start_line: $marker" >&2
  tail -200 build/screenshots/flutter-run.log >&2 || true
  return 1
}

run_flutter_drive_logged() {
  local timeout_seconds="$1"
  local log_mode="$2"
  shift 2
  python3 - "$timeout_seconds" "$log_mode" build/screenshots/flutter-run.log "$@" <<'PY'
import os
import selectors
import signal
import subprocess
import sys
import time

timeout_seconds = int(sys.argv[1])
log_mode = sys.argv[2]
log_path = sys.argv[3]
cmd = sys.argv[4:]
deadline = time.monotonic() + timeout_seconds
selector = selectors.DefaultSelector()

with open(log_path, 'w' if log_mode == 'write' else 'a', buffering=1) as log:
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        preexec_fn=os.setsid,
    )
    selector.register(proc.stdout, selectors.EVENT_READ)
    timed_out = False
    while proc.poll() is None:
        for key, _ in selector.select(timeout=1):
            line = key.fileobj.readline()
            if line:
                sys.stdout.write(line)
                sys.stdout.flush()
                log.write(line)
        if time.monotonic() > deadline:
            timed_out = True
            message = f'JRI_FLUTTER_DRIVE_TIMEOUT_AFTER_SECONDS={timeout_seconds}\n'
            sys.stderr.write(message)
            log.write(message)
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
            except ProcessLookupError:
                pass
            except Exception:
                proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                except ProcessLookupError:
                    pass
                except Exception:
                    proc.kill()
                proc.wait()
            break
    remaining = proc.stdout.read() if proc.stdout else ''
    if remaining:
        sys.stdout.write(remaining)
        sys.stdout.flush()
        log.write(remaining)
    sys.exit(124 if timed_out else proc.returncode)
PY
}

terminate_background_drive() {
  local drive_pid="$1"
  if ! kill -0 "$drive_pid" >/dev/null 2>&1; then
    wait "$drive_pid" >/dev/null 2>&1 || true
    return 0
  fi

  pkill -TERM -P "$drive_pid" >/dev/null 2>&1 || true
  kill "$drive_pid" >/dev/null 2>&1 || true
  for _ in {1..10}; do
    if ! kill -0 "$drive_pid" >/dev/null 2>&1; then
      wait "$drive_pid" >/dev/null 2>&1 || true
      return 0
    fi
    sleep 1
  done

  pkill -KILL -P "$drive_pid" >/dev/null 2>&1 || true
  kill -KILL "$drive_pid" >/dev/null 2>&1 || true
  wait "$drive_pid" >/dev/null 2>&1 || true
}

run_long_markdown_drive_with_background_controls() {
  local marker_start_line
  marker_start_line=$(($(wc -l < build/screenshots/flutter-run.log) + 1))
  run_flutter_drive_logged 3600 append \
    flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/emulator_long_markdown_flow_test.dart \
    -d "$DEVICE_ID" \
    --dart-define=JRI_EXPORT_TTS_WAV=true \
    --dart-define=JRI_DEFAULT_VOICE_ID=flite-classic \
    --dart-define=JRI_EXPECTED_LONG_DOC_VOICE_LABEL='Motorola Male (Flite)' \
    --dart-define=JRI_ENABLE_IMPORT_PATH_DIALOG=true \
    --dart-define=JRI_VALIDATE_BACKGROUND_MEDIA=true \
    --dart-define=JRI_BACKGROUND_MEDIA_EXTERNAL_CONTROLS=false &
  local drive_pid=$!

  if ! wait_for_log_after_line "JRI_BACKGROUND_VALIDATION_READY" 1200 "$marker_start_line"; then
    xcrun simctl terminate "$DEVICE_ID" com.example.justReadIt || true
    terminate_background_drive "$drive_pid"
    return 1
  fi
  xcrun simctl launch "$DEVICE_ID" com.apple.springboard >/dev/null 2>&1 || true
  sleep 8
  xcrun simctl io "$DEVICE_ID" screenshot build/screenshots/background-ios-home.png || true
  xcrun simctl launch "$DEVICE_ID" com.example.justReadIt >/dev/null 2>&1 || true

  wait "$drive_pid"
}

DEVICE_ID="${IOS_DEVICE_ID:-$(resolve_simulator)}"
xcrun simctl shutdown "$DEVICE_ID" >/dev/null 2>&1 || true
xcrun simctl erase "$DEVICE_ID"
xcrun simctl boot "$DEVICE_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE_ID" -b

if ! run_flutter_drive_logged 600 write \
  flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/emulator_flow_test.dart \
    -d "$DEVICE_ID" \
    --dart-define=JRI_EXPORT_TTS_WAV=true \
    --dart-define=JRI_ENABLE_IMPORT_PATH_DIALOG=true; then
  collect_simulator_diagnostics short-flow-retry
  xcrun simctl terminate "$DEVICE_ID" com.example.justReadIt || true
  xcrun simctl uninstall "$DEVICE_ID" com.example.justReadIt || true
  run_flutter_drive_logged 600 write \
    flutter drive \
      --driver=test_driver/integration_test.dart \
      --target=integration_test/emulator_flow_test.dart \
      -d "$DEVICE_ID" \
      --dart-define=JRI_EXPORT_TTS_WAV=true \
      --dart-define=JRI_ENABLE_IMPORT_PATH_DIALOG=true
fi

xcrun simctl terminate "$DEVICE_ID" com.example.justReadIt || true
xcrun simctl uninstall "$DEVICE_ID" com.example.justReadIt || true

if ! run_long_markdown_drive_with_background_controls; then
  collect_simulator_diagnostics long-flow-retry
  xcrun simctl terminate "$DEVICE_ID" com.example.justReadIt || true
  xcrun simctl uninstall "$DEVICE_ID" com.example.justReadIt || true
  run_long_markdown_drive_with_background_controls
fi

if ! grep -q "JRI_LONG_DOC_FULL_TEXT_PLAYBACK_VALIDATED" build/screenshots/flutter-run.log; then
  echo "Full long markdown playback was not validated" >&2
  exit 1
fi
if ! grep -q "JRI_LONG_DOC_PLAYBACK_STARTED_AFTER_MS" build/screenshots/flutter-run.log; then
  echo "Long document playback-start latency was not measured" >&2
  exit 1
fi
for marker in \
  JRI_BACKGROUND_PLAYBACK_CONTINUED \
  JRI_BACKGROUND_REMOTE_PAUSE_VALIDATED \
  JRI_BACKGROUND_REMOTE_PLAY_VALIDATED; do
  if ! grep -q "$marker" build/screenshots/flutter-run.log; then
    echo "Background media marker missing: $marker" >&2
    exit 1
  fi
done

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
"$VENV_DIR/bin/python" -m pip install vosk==0.3.44
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
if [ -s build/screenshots/background-ios-home.png ]; then
  python3 ../tools/validate_pngs.py build/screenshots/background-ios-home.png
fi

xcrun simctl io "$DEVICE_ID" screenshot build/screenshots/final-ios-simulator.png || true
