#!/usr/bin/env bash
set -euxo pipefail

mkdir -p build/screenshots
flutter run -t lib/screenshot_app.dart -d emulator-5554 --debug --no-pub > build/screenshots/flutter-run.log 2>&1 &
RUN_PID=$!
trap 'kill "$RUN_PID" >/dev/null 2>&1 || true' EXIT

for _ in $(seq 1 120); do
  if adb shell pidof com.example.just_read_it >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! adb shell pidof com.example.just_read_it >/dev/null 2>&1; then
  echo "App did not start" >&2
  cat build/screenshots/flutter-run.log >&2 || true
  exit 1
fi

sleep 5
adb exec-out screencap -p > build/screenshots/01_editor_mobile.png
adb shell input tap 195 785
sleep 3
adb exec-out screencap -p > build/screenshots/02_player_mobile.png

test -s build/screenshots/01_editor_mobile.png
test -s build/screenshots/02_player_mobile.png
