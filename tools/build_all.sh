#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
RUST_DIR="$ROOT_DIR/rust_core"
FLUTTER_DIR="$ROOT_DIR/flutter_client"
RUST_FEATURES="${RUST_FEATURES:-bridge,piper}"
export PATH="/opt/cargo/bin:$PATH"

normalize_for_local_properties() {
  python3 - "$1" <<'PY'
import os
import sys

path = sys.argv[1]
print(os.path.abspath(os.path.expanduser(path)).replace('\\', '/'))
PY
}

sync_local_properties() {
  local props="$FLUTTER_DIR/android/local.properties"
  local sdk_dir="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  local flutter_bin
  flutter_bin="$(command -v flutter || true)"

  if [[ -z "$flutter_bin" ]]; then
    echo "[build] flutter binary not found on PATH" >&2
    exit 1
  fi
  if [[ -z "$sdk_dir" ]]; then
    echo "[build] ANDROID_SDK_ROOT or ANDROID_HOME must be set to build Flutter artifacts" >&2
    exit 1
  fi

  local flutter_root
  flutter_root="${FLUTTER_ROOT:-$(cd "$(dirname "$flutter_bin")/.." && pwd -P)}"
  local normalized_sdk normalized_flutter
  normalized_sdk="$(normalize_for_local_properties "$sdk_dir")"
  normalized_flutter="$(normalize_for_local_properties "$flutter_root")"

  mkdir -p "$(dirname "$props")"
  local tmp
  tmp="$(mktemp)"
  local saw_sdk=false
  local saw_flutter=false

  if [[ -f "$props" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      case "$line" in
        sdk.dir=*)
          printf 'sdk.dir=%s\n' "$normalized_sdk" >>"$tmp"
          saw_sdk=true
          ;;
        flutter.sdk=*)
          printf 'flutter.sdk=%s\n' "$normalized_flutter" >>"$tmp"
          saw_flutter=true
          ;;
        *)
          printf '%s\n' "$line" >>"$tmp"
          ;;
      esac
    done <"$props"
  fi

  if [[ "$saw_sdk" != true ]]; then
    printf 'sdk.dir=%s\n' "$normalized_sdk" >>"$tmp"
  fi
  if [[ "$saw_flutter" != true ]]; then
    printf 'flutter.sdk=%s\n' "$normalized_flutter" >>"$tmp"
  fi

  mv "$tmp" "$props"
}

usage() {
  cat <<USAGE
Build orchestrator for the TTS Beast stack.

Usage: $0 [options] [steps]

Options:
  --ort-base DIR     Override ORT_LIB_BASE per run
  --features LIST    Comma-separated Rust features (default: bridge,piper)

Steps:
  rust         Build the Rust core for the host machine
  android      Cross-compile Rust core with cargo-ndk
  ios          Produce universal static library with cargo lipo
  flutter      Run flutter build apk --debug (requires Android SDK)
  codegen      Execute flutter_rust_bridge_codegen
  all          Execute rust + codegen + flutter (default)
USAGE
}

run_codegen() {
  echo "[build] Generating Flutter Rust Bridge bindings"
  local stub_path="$ROOT_DIR/tools/stubs"
  local config_file="$ROOT_DIR/flutter_rust_bridge.yaml"
  if [[ ! -f "$config_file" ]]; then
    echo "[build] Missing flutter_rust_bridge.yaml next to tools/" >&2
    exit 1
  fi
  if ! command -v flutter_rust_bridge_codegen >/dev/null 2>&1; then
    cat <<'EOF' >&2
[build] flutter_rust_bridge_codegen not found on PATH.
[build] Install it via: cargo install flutter_rust_bridge_codegen --locked
EOF
    exit 1
  fi
  PATH="$stub_path:$PATH" flutter_rust_bridge_codegen generate \
    --config-file "$config_file"
}

build_rust() {
  echo "[build] Building Rust core"
  (cd "$RUST_DIR" && cargo build --features "$RUST_FEATURES")
}

build_android() {
  echo "[build] Building Android shared libraries"
  local output_dir="$FLUTTER_DIR/android/app/src/main/jniLibs"
  local -a targets=("armeabi-v7a" "arm64-v8a" "x86_64")
  mkdir -p "$output_dir"

  for abi in "${targets[@]}"; do
    echo "[build] -> ABI ${abi}"
    if [[ -n "${ORT_LIB_BASE:-}" ]]; then
      local candidate="${ORT_LIB_BASE}/${abi}"
      if [[ -d "$candidate" ]]; then
        echo "[build]    using ONNX Runtime from $candidate"
        (cd "$RUST_DIR" && ORT_LIB_LOCATION="$candidate" cargo ndk -t "$abi" -o "$output_dir" build --release --features "$RUST_FEATURES")
        if [[ -f "${candidate}/libonnxruntime.so" ]]; then
          cp "${candidate}/libonnxruntime.so" "${output_dir}/${abi}/"
        fi
        copy_cxx_shared "$abi" "$output_dir"
        continue
      else
        echo "[build]    warning: $candidate not found; falling back to default ORT build"
      fi
    fi
    (cd "$RUST_DIR" && cargo ndk -t "$abi" -o "$output_dir" build --release --features "$RUST_FEATURES")
    local built_ort
    built_ort="$(find "$RUST_DIR/target/${abi}/release/build" -maxdepth 2 -path '*ort-sys*/out/libonnxruntime.so' -print -quit || true)"
    if [[ -n "$built_ort" ]]; then
      cp "$built_ort" "${output_dir}/${abi}/"
    fi
    copy_cxx_shared "$abi" "$output_dir"
  done
}

copy_cxx_shared() {
  local abi="$1"
  local dest_root="$2"
  local ndk="${ANDROID_NDK_HOME:-${ANDROID_NDK:-}}"
  local host_tag="${NDK_HOST_TAG:-linux-x86_64}"
  case "${OSTYPE:-}" in
    msys*|cygwin*|win*|Win*) host_tag="${NDK_HOST_TAG:-windows-x86_64}" ;;
  esac
  if [[ -z "$ndk" ]]; then
    echo "[build]    warning: ANDROID_NDK_HOME not set; cannot copy libc++_shared.so"
    return
  fi
  if [[ "$ndk" =~ ^[A-Za-z]: ]]; then
    if command -v cygpath >/dev/null 2>&1; then
      ndk="$(cygpath -u "$ndk")"
    else
      ndk="${ndk//\\//}"
    fi
  fi
  local triple subdir
  case "$abi" in
    arm64-v8a)
      triple="aarch64-linux-android"
      subdir="lib64"
      ;;
    armeabi-v7a)
      triple="arm-linux-androideabi"
      subdir="lib"
      ;;
    x86_64)
      triple="x86_64-linux-android"
      subdir="lib64"
      ;;
    x86)
      triple="i686-linux-android"
      subdir="lib"
      ;;
    *) return ;;
  esac
  local src="$ndk/toolchains/llvm/prebuilt/${host_tag}/sysroot/usr/lib/${triple}/${subdir}/libc++_shared.so"
  if [[ ! -f "$src" ]]; then
    src="$ndk/toolchains/llvm/prebuilt/${host_tag}/sysroot/usr/lib/${triple}/libc++_shared.so"
  fi
  if [[ ! -f "$src" ]]; then
    src="$ndk/sources/cxx-stl/llvm-libc++/libs/${abi}/libc++_shared.so"
  fi
  if [[ -f "$src" ]]; then
    mkdir -p "${dest_root}/${abi}"
    cp "$src" "${dest_root}/${abi}/"
  else
    echo "[build]    warning: $src not found; libc++_shared.so missing for $abi"
  fi
}

build_ios() {
  echo "[build] Building iOS universal library"
  (cd "$RUST_DIR" && cargo lipo --release --features "$RUST_FEATURES")
}

build_flutter() {
  echo "[build] Building Flutter client"
  sync_local_properties
  (
    cd "$FLUTTER_DIR"
    flutter pub get
    flutter build apk --debug
  )
}

main() {
  local ort_override=""
  local steps=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ort-base)
        shift
        ort_override="$1"
        ;;
      --features)
        shift
        RUST_FEATURES="$1"
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        steps+=("$1")
        ;;
    esac
    shift || true
  done

  if [[ -n "$ort_override" ]]; then
    export ORT_LIB_BASE="$ort_override"
  fi

  if [[ ${#steps[@]} -eq 0 ]]; then
    steps=(codegen rust flutter)
  fi

  for step in "${steps[@]}"; do
    case "$step" in
      rust) build_rust ;;
      android) build_android ;;
      ios) build_ios ;;
      flutter) build_flutter ;;
      codegen) run_codegen ;;
      all)
        run_codegen
        build_rust
        build_flutter
        ;;
      *)
        usage
        exit 1
        ;;
    esac
  done
}

main "$@"
