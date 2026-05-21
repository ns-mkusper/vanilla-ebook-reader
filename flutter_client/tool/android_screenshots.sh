#!/usr/bin/env bash
set -euxo pipefail

mkdir -p build/screenshots
flutter run -t lib/screenshot_app.dart -d emulator-5554 --debug --no-pub > build/screenshots/flutter-run.log 2>&1 &
RUN_PID=$!
trap 'kill "$RUN_PID" >/dev/null 2>&1 || true' EXIT

dump_ui() {
  local name="$1"
  adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
  adb shell cat /sdcard/window.xml > "build/screenshots/${name}.xml" 2>/dev/null || true
  adb shell dumpsys window > "build/screenshots/${name}-window.log" 2>/dev/null || true
}

clear_system_dialogs() {
  local name="$1"
  for attempt in $(seq 1 5); do
    dump_ui "${name}-attempt-${attempt}"
    if ! grep -Eiq "isn't responding|is not responding|System UI|Close app|Wait" "build/screenshots/${name}-attempt-${attempt}.xml"; then
      cp "build/screenshots/${name}-attempt-${attempt}.xml" "build/screenshots/${name}.xml"
      cp "build/screenshots/${name}-attempt-${attempt}-window.log" "build/screenshots/${name}-window.log"
      return 0
    fi
    echo "System dialog/ANR detected before screenshot $name; choosing Wait and retrying" >&2
    if grep -q 'resource-id="android:id/aerr_wait"' "build/screenshots/${name}-attempt-${attempt}.xml"; then
      adb shell input tap 540 1300
    else
      adb shell input keyevent BACK
    fi
    sleep 8
  done
  echo "System dialog/ANR remained before screenshot $name" >&2
  cat "build/screenshots/${name}-attempt-5.xml" >&2 || true
  exit 1
}

assert_app_foreground() {
  local name="$1"
  if ! grep -Eq "com\.example\.just_read_it|MainActivity" "build/screenshots/${name}-window.log"; then
    echo "Just Read It is not the focused app before screenshot $name" >&2
    grep -E "mCurrentFocus|mFocusedApp|topResumedActivity" "build/screenshots/${name}-window.log" >&2 || true
    exit 1
  fi
}

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

for _ in $(seq 1 120); do
  if grep -q 'JRI_SCREENSHOT_READY' build/screenshots/flutter-run.log; then
    break
  fi
  sleep 2
done

if ! grep -q 'JRI_SCREENSHOT_READY' build/screenshots/flutter-run.log; then
  echo "Flutter UI did not report readiness" >&2
  cat build/screenshots/flutter-run.log >&2 || true
  exit 1
fi

sleep 2
clear_system_dialogs 01_editor_mobile
assert_app_foreground 01_editor_mobile
adb exec-out screencap -p > build/screenshots/01_editor_mobile.png
adb shell input tap 195 785
sleep 3
clear_system_dialogs 02_player_mobile
assert_app_foreground 02_player_mobile
adb exec-out screencap -p > build/screenshots/02_player_mobile.png

test -s build/screenshots/01_editor_mobile.png
test -s build/screenshots/02_player_mobile.png
python3 ../tools/validate_pngs.py build/screenshots/01_editor_mobile.png build/screenshots/02_player_mobile.png
