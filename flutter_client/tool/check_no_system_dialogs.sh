#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/screenshots
adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
adb shell cat /sdcard/window.xml > build/screenshots/final-ui.xml 2>/dev/null || true
adb shell dumpsys window > build/screenshots/final-window.log 2>/dev/null || true
if grep -Eiq "isn't responding|is not responding|System UI|Close app|Wait" build/screenshots/final-ui.xml; then
  echo "System dialog/ANR detected after emulator flow" >&2
  cat build/screenshots/final-ui.xml >&2
  exit 1
fi
