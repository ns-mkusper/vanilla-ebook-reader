#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
RUST_DIR="$ROOT_DIR/rust_core"
FLUTTER_DIR="$ROOT_DIR/flutter_client"

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
  PATH="$stub_path:$PATH" flutter_rust_bridge_codegen generate \
    --rust-root "$RUST_DIR" \
    --rust-input crate::api \
    --rust-output "$RUST_DIR/src/bridge_generated.rs" \
    --dart-output "$FLUTTER_DIR/lib" \
    --dart-entrypoint-class-name TtsBridge \
    --no-deps-check \
    --no-dart-format \
    --rust-features bridge
}

build_rust() {
  echo "[build] Building Rust core"
  (cd "$RUST_DIR" && cargo build)
}

build_android() {
  echo "[build] Building Android shared libraries"
  (cd "$RUST_DIR" && cargo ndk -t armeabi-v7a -t arm64-v8a -t x86_64 -o "$FLUTTER_DIR/android/app/src/main/jniLibs" build --release)
}

build_ios() {
  echo "[build] Building iOS universal library"
  (cd "$RUST_DIR" && cargo lipo --release)
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
