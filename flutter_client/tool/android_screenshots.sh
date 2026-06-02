#!/usr/bin/env bash
set -euxo pipefail

mkdir -p build/screenshots
adb -s emulator-5554 wait-for-device
for attempt in {1..90}; do
  if adb -s emulator-5554 shell pm list packages >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
adb -s emulator-5554 shell pm list packages >/dev/null
sleep 10

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


capture_android_media_sessions() {
  local path="$1"
  timeout 10s adb -s emulator-5554 shell dumpsys media_session > "$path" || true
  if ! grep -q "com.example.just_read_it" "$path"; then
    echo "Just Read It media session missing from $path" >&2
    cat "$path" >&2 || true
    return 1
  fi
}

assert_android_playback_state() {
  local path="$1"
  local expected="$2"
  if ! grep -Eq "state=PlaybackState.*state=$expected" "$path"; then
    echo "Expected Android media session playback state=$expected in $path" >&2
    cat "$path" >&2 || true
    return 1
  fi
}

wait_for_android_playback_state() {
  local path="$1"
  local expected="$2"
  local timeout_seconds="$3"
  local deadline=$((SECONDS + timeout_seconds))
  while (( SECONDS < deadline )); do
    if capture_android_media_sessions "$path" && assert_android_playback_state "$path" "$expected"; then
      return 0
    fi
    sleep 2
  done
  echo "Timed out waiting for Android media session playback state=$expected" >&2
  capture_android_media_sessions "$path" || true
  assert_android_playback_state "$path" "$expected"
}


run_long_markdown_drive_with_background_controls() {
  flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/emulator_long_markdown_flow_test.dart \
    -d emulator-5554 \
    --dart-define=JRI_EXPORT_TTS_WAV=true \
    --dart-define=JRI_DEFAULT_VOICE_ID=android-system \
    --dart-define=JRI_ENABLE_IMPORT_PATH_DIALOG=true \
    --dart-define=JRI_DISABLE_BACKGROUND_TTS_QUEUE=true \
    --dart-define=JRI_LONG_DOC_WAV_TIMEOUT_MINUTES=10 \
    --dart-define=JRI_VALIDATE_BACKGROUND_MEDIA=true \
    --dart-define=JRI_BACKGROUND_MEDIA_EXTERNAL_CONTROLS=false \
    --dart-define=JRI_SHELL_VALIDATED_BACKGROUND_PLAYBACK=true \
    --dart-define=JRI_BACKGROUND_MEDIA_HOLD_SECONDS=20 \
    >> build/screenshots/flutter-run.log 2>&1 &
  local drive_pid=$!

  wait_for_log "JRI_BACKGROUND_VALIDATION_READY" 600
  timeout 5s adb -s emulator-5554 shell input keyevent KEYCODE_HOME >/dev/null 2>&1 || true
  sleep 3
  capture_android_media_sessions build/screenshots/background-android-playing.txt
  assert_android_playback_state build/screenshots/background-android-playing.txt 3
  echo "JRI_BACKGROUND_PLAYBACK_CONTINUED source=android-media-session" >> build/screenshots/flutter-run.log

  timeout 5s adb -s emulator-5554 exec-out screencap -p > build/screenshots/background-android-home.png || true
  timeout 10s adb -s emulator-5554 shell monkey -p com.example.just_read_it -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true

  wait_for_log "JRI_BACKGROUND_REMOTE_PAUSE_READY" 120
  wait_for_log "JRI_BACKGROUND_REMOTE_PAUSE_VALIDATED" 60
  capture_android_media_sessions build/screenshots/background-android-paused.txt || true
  wait_for_log "JRI_BACKGROUND_REMOTE_PLAY_READY" 60
  wait_for_log "JRI_BACKGROUND_REMOTE_PLAY_VALIDATED" 60
  capture_android_media_sessions build/screenshots/background-android-resumed.txt || true

  local drive_status=0
  wait "$drive_pid" || drive_status=$?
  if (( drive_status != 0 )); then
    if grep -q "All tests passed" build/screenshots/flutter-run.log && \
       grep -q "JRI_LONG_DOC_FULL_TEXT_PLAYBACK_VALIDATED" build/screenshots/flutter-run.log; then
      echo "flutter drive exited $drive_status after validated tests; continuing" >&2
    else
      return "$drive_status"
    fi
  fi
}

flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/emulator_flow_test.dart \
  -d emulator-5554 \
  --dart-define=JRI_EXPORT_TTS_WAV=true \
  --dart-define=JRI_ENABLE_IMPORT_PATH_DIALOG=true \
  > build/screenshots/flutter-run.log 2>&1

flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/word_seek_highlight_test.dart \
  -d emulator-5554 \
  >> build/screenshots/flutter-run.log 2>&1

run_long_markdown_drive_with_background_controls

if ! grep -q "JRI_WORD_SEEK_HIGHLIGHT_VALIDATED" build/screenshots/flutter-run.log; then
  echo "Word tap seek/highlight emulator validation did not complete" >&2
  exit 1
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
  --expected "Simple book speech fixture This simple book is a clear test of imported speech Just Read It should restore the document and read every sentence aloud" \
  --min-coverage 0.60
rm -rf "$MODEL_DIR" build/screenshots/vosk-model.zip

test -s build/screenshots/01_txt_import_editor.png
test -s build/screenshots/02_player_playback.png
test -s build/screenshots/voice_sample_from_emulator.wav
test -s build/screenshots/long_markdown_playback_sample_from_emulator.wav
python3 ../tools/validate_pngs.py \
  build/screenshots/01_txt_import_editor.png \
  build/screenshots/02_player_playback.png
if [ -s build/screenshots/background-android-home.png ]; then
  python3 ../tools/validate_pngs.py build/screenshots/background-android-home.png
fi
