#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/screenshots
adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
adb shell cat /sdcard/window.xml > build/screenshots/final-ui.xml 2>/dev/null || true
adb shell dumpsys window > build/screenshots/final-window.log 2>/dev/null || true
if grep -Eiq "isn't responding|is not responding|Close app|Wait" build/screenshots/final-ui.xml; then
  if ! grep -Eiq "just read it|just_read_it" build/screenshots/final-ui.xml && \
     ! grep -Eiq "Application Not Responding: com\.example\.just_read_it" build/screenshots/final-window.log; then
    echo "Emulator/system ANR detected after app validation; ignoring non-app process dialog" >&2
    cat build/screenshots/final-ui.xml >&2
    exit 0
  fi
  echo "App/system dialog detected after emulator flow" >&2
  cat build/screenshots/final-ui.xml >&2
  exit 1
fi
