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

## iOS Rust library build

On macOS with Xcode installed, build the Rust Flite bridge for iOS simulator/device targets:

```bash
./tools/build_all.sh ios
```

The Flutter iOS Xcode project also runs `flutter_client/tool/ios_build_rust_core.sh` during app builds. That script compiles `rust_core` with `--no-default-features --features bridge,flite`, writes `librust_core.a` into Xcode's built-products directory, and links it into the app so Flutter Rust Bridge can resolve symbols with `DynamicLibrary.process()`.

## Android Rust library build

```bash
cd rust_core
cargo ndk -t arm64-v8a \
  -o ../flutter_client/android/app/src/main/jniLibs \
  build --no-default-features --features bridge,flite
```

## iOS simulator build

On macOS with Xcode installed:

```bash
cd flutter_client
flutter build ios --simulator --debug
```

For a signed physical iPhone development build, open `flutter_client/ios/Runner.xcworkspace` in Xcode, select a development team and bundle identifier, then build/run the `Runner` scheme on the device.

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

## iOS simulator screenshot and audio proof

When an iOS simulator is available on macOS:

```bash
cd flutter_client
bash tool/ios_screenshots.sh
```

That script mirrors the Android emulator proof while keeping Rust Flite as the iOS TTS backend. It validates launch, TXT/EPUB import, persistence, Rust-backed playback, pause/resume, highlighting, screenshots, playback-sourced WAV artifacts, WAV voiced-audio checks, STT coverage, background/minimized playback continuation, background-control callbacks, and iOS-specific native/plugin/Rust loading log failures. The required log markers include `JRI_BACKGROUND_PLAYBACK_CONTINUED`, `JRI_BACKGROUND_REMOTE_PAUSE_VALIDATED`, and `JRI_BACKGROUND_REMOTE_PLAY_VALIDATED`, plus a `background-ios-home.png` simulator screenshot when screenshot capture is available.

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
- validates that minimized/background playback continues after pressing Home;
- validates Android media-session pause/play controls while the app is backgrounded;
- requires `JRI_BACKGROUND_PLAYBACK_CONTINUED`, `JRI_BACKGROUND_REMOTE_PAUSE_VALIDATED`, and `JRI_BACKGROUND_REMOTE_PLAY_VALIDATED` log markers;
- captures a `background-android-home.png` proof screenshot when screenshot capture is available;
- validates that no native plugin or AudioService binding errors appeared in logs.

## CI expectations

The PR is considered mergeable only when all CI jobs pass:

- `rust-lint-and-test`
- `android-rust-check`
- `ios-rust-check`
- `flutter-ux-tests`
- `android-emulator-screenshots`
- `ios-simulator-screenshots`
