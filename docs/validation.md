# Validation guide

This document collects the validation commands used to keep Just Read It mergeable. Run the smallest useful set while developing, then run the broader suite before release-oriented changes.

## Flutter checks

Run static analysis:

```bash
cd flutter_client
flutter analyze
```

Run the full Flutter test suite:

```bash
flutter test
```

Run focused suites:

```bash
flutter test test/document_repository_test.dart
flutter test test/ux_flow_test.dart
flutter test test/tts_chunking_test.dart
flutter test test/performance/text_pipeline_perf_test.dart
```

## Rust checks

```bash
cd rust_core
cargo fmt --check
cargo clippy -- -D warnings
cargo test --no-default-features --features flite
cargo check --target aarch64-linux-android --no-default-features
```

## Android Rust library build

```bash
cd rust_core
cargo ndk -t arm64-v8a \
  -o ../flutter_client/android/app/src/main/jniLibs \
  build --no-default-features --features bridge,flite
```

## APK build

```bash
cd flutter_client
flutter build apk --debug --target-platform android-arm64
```

On ARM64 Linux hosts, Android build tools may need x86_64 compatibility libraries available through `LD_LIBRARY_PATH`:

```bash
LD_LIBRARY_PATH=/usr/x86_64-linux-gnu/lib:/usr/x86_64-linux-gnu/lib64 \
  flutter build apk --debug --target-platform android-arm64
```

## Emulator screenshot and audio proof

When an Android emulator is available:

```bash
cd flutter_client
bash tool/android_screenshots.sh
```

That script validates the full mobile UX path:

- imports fixture documents through the app UI;
- verifies draft persistence across an in-process app restart;
- starts native read-aloud playback;
- captures editor and player screenshots;
- exports playback-sourced WAV artifacts;
- validates WAV headers and voiced audio windows;
- checks speech-to-text coverage for the short playback sample;
- validates that no native plugin or AudioService binding errors appeared in logs.

## CI expectations

The PR is considered mergeable only when all CI jobs pass:

- `rust-lint-and-test`
- `android-rust-check`
- `flutter-ux-tests`
- `android-emulator-screenshots`
