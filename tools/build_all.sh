#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
RUST_DIR="$ROOT_DIR/rust_core"
FLUTTER_DIR="$ROOT_DIR/flutter_client"
RUST_FEATURES="${RUST_FEATURES:-bridge,piper}"
export PATH="/opt/cargo/bin:$PATH"

usage() {
  cat <<USAGE
Build orchestrator for the TTS Beast stack.

Usage: $0 [steps]

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
  (cd "$RUST_DIR" && cargo ndk -t armeabi-v7a -t arm64-v8a -t x86_64 -o "$FLUTTER_DIR/android/app/src/main/jniLibs" build --release --features "$RUST_FEATURES")
}

build_ios() {
  echo "[build] Building iOS universal library"
  (cd "$RUST_DIR" && cargo lipo --release --features "$RUST_FEATURES")
}

build_flutter() {
  echo "[build] Building Flutter client"
  (cd "$FLUTTER_DIR" && flutter build apk --debug)
}

main() {
  if [[ $# -eq 0 ]]; then
    run_codegen
    build_rust
    build_flutter
    exit 0
  fi

  for step in "$@"; do
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
