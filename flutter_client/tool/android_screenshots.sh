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

assert_no_system_dialog() {
  local name="$1"
  dump_ui "$name"
  if grep -Eiq "isn't responding|is not responding|System UI|Close app|Wait" "build/screenshots/${name}.xml"; then
    echo "System dialog/ANR detected before screenshot $name" >&2
    cat "build/screenshots/${name}.xml" >&2
    exit 1
  fi
}

assert_app_foreground() {
  local name="$1"
  dump_ui "$name"
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
assert_no_system_dialog 01_editor_mobile
assert_app_foreground 01_editor_mobile
adb exec-out screencap -p > build/screenshots/01_editor_mobile.png
adb shell input tap 195 785
sleep 3
assert_no_system_dialog 02_player_mobile
assert_app_foreground 02_player_mobile
adb exec-out screencap -p > build/screenshots/02_player_mobile.png

test -s build/screenshots/01_editor_mobile.png
test -s build/screenshots/02_player_mobile.png
python3 - <<'PY'
import struct, zlib
from pathlib import Path

def nonwhite_ratio(path):
    data = Path(path).read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise SystemExit(f'{path} is not a PNG')
    pos = 8
    idat = b''
    while pos < len(data):
        ln = struct.unpack('>I', data[pos:pos+4])[0]
        typ = data[pos+4:pos+8]
        chunk = data[pos+8:pos+8+ln]
        pos += 12 + ln
        if typ == b'IHDR':
            w, h, bit, ctype, *_ = struct.unpack('>IIBBBBB', chunk)
        elif typ == b'IDAT':
            idat += chunk
        elif typ == b'IEND':
            break
    bpp = {2: 3, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = w * bpp
    prev = [0] * stride
    idx = 0
    nonwhite = 0
    for _ in range(h):
        ft = raw[idx]
        idx += 1
        scan = list(raw[idx:idx+stride])
        idx += stride
        recon = [0] * stride
        for x, a in enumerate(scan):
            left = recon[x-bpp] if x >= bpp else 0
            up = prev[x]
            ul = prev[x-bpp] if x >= bpp else 0
            if ft == 0:
                val = a
            elif ft == 1:
                val = (a + left) & 255
            elif ft == 2:
                val = (a + up) & 255
            elif ft == 3:
                val = (a + ((left + up) // 2)) & 255
            else:
                p = left + up - ul
                pa, pb, pc = abs(p-left), abs(p-up), abs(p-ul)
                pr = left if pa <= pb and pa <= pc else up if pb <= pc else ul
                val = (a + pr) & 255
            recon[x] = val
        prev = recon
        for j in range(0, stride, bpp):
            r, g, b = recon[j], recon[j+1], recon[j+2]
            if not (r > 245 and g > 245 and b > 245):
                nonwhite += 1
    return nonwhite / (w * h)

for path in ['build/screenshots/01_editor_mobile.png', 'build/screenshots/02_player_mobile.png']:
    ratio = nonwhite_ratio(path)
    print(f'{path}: non-white ratio {ratio:.3f}')
    if ratio < 0.20:
        raise SystemExit(f'{path} looks blank/white')
PY
