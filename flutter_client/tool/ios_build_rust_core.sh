#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUST_DIR="$ROOT_DIR/rust_core"
OUT_DIR="${BUILT_PRODUCTS_DIR:-$ROOT_DIR/flutter_client/build/ios-rust}"
FEATURES="${JRI_RUST_FEATURES:-bridge,flite}"
PROFILE="debug"
CARGO_FLAGS=()

if [[ "${CONFIGURATION:-Debug}" != "Debug" ]]; then
  PROFILE="release"
  CARGO_FLAGS+=(--release)
fi

sdk_name="${SDK_NAME:-iphonesimulator}"
platform_name="${PLATFORM_NAME:-}"
archs="${ARCHS:-${CURRENT_ARCH:-}}"
if [[ -z "$archs" || "$archs" == "undefined_arch" ]]; then
  case "$sdk_name" in
    iphoneos*) archs="arm64" ;;
    *) archs="$(uname -m)" ;;
  esac
fi

rust_targets=()
for arch in $archs; do
  case "$sdk_name:$platform_name:$arch" in
    iphoneos*:*:arm64|*:iphoneos:arm64)
      rust_targets+=("aarch64-apple-ios")
      ;;
    iphonesimulator*:*:arm64|*:iphonesimulator:arm64)
      rust_targets+=("aarch64-apple-ios-sim")
      ;;
    iphonesimulator*:*:x86_64|*:iphonesimulator:x86_64)
      rust_targets+=("x86_64-apple-ios")
      ;;
    *)
      echo "Unsupported iOS Rust target for SDK_NAME=$sdk_name PLATFORM_NAME=$platform_name ARCH=$arch" >&2
      exit 1
      ;;
  esac
done

# De-duplicate targets while preserving order.
unique_targets=()
for target in "${rust_targets[@]}"; do
  seen=false
  for existing in "${unique_targets[@]}"; do
    if [[ "$existing" == "$target" ]]; then
      seen=true
      break
    fi
  done
  if [[ "$seen" == false ]]; then
    unique_targets+=("$target")
  fi
done

mkdir -p "$OUT_DIR"
libs=()
for target in "${unique_targets[@]}"; do
  echo "[ios-rust] building $target profile=$PROFILE features=$FEATURES"
  rustup target add "$target" >/dev/null
  (
    cd "$RUST_DIR"
    cargo build \
      --target "$target" \
      --no-default-features \
      --features "$FEATURES" \
      "${CARGO_FLAGS[@]}"
  )
  lib="$RUST_DIR/target/$target/$PROFILE/librust_core.a"
  if [[ ! -f "$lib" ]]; then
    echo "Expected Rust static library not found: $lib" >&2
    exit 1
  fi
  libs+=("$lib")
done

if [[ ${#libs[@]} -eq 1 ]]; then
  cp "${libs[0]}" "$OUT_DIR/librust_core.a"
else
  lipo -create "${libs[@]}" -output "$OUT_DIR/librust_core.a"
fi

# The Xcode target links this exact file with -force_load so Flutter Rust
# Bridge symbols are visible through DynamicLibrary.process() on iOS.
echo "[ios-rust] wrote $OUT_DIR/librust_core.a"
