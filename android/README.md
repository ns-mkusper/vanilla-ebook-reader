# Android Scaffolding

This directory contains placeholders for building the Vanilla Ebook Reader on Android. The current Rust crates expose the app logic as a `cdylib` (`libebook_reader.so`) so that it can be called from an Android entry point.

## Quick Start

1. Install the Android SDK, NDK (r26 or newer), and configure `ANDROID_HOME` / `ANDROID_NDK_HOME`.
2. Install supporting tooling:
   ```bash
   cargo install cargo-ndk
   cargo install just # optional helper
   ```
3. Build the Rust shared library for the desired ABI (include `--features native-audio` to pull in the Rodio/CPAL backend):
   ```bash
   cargo ndk -t arm64-v8a -o android/app/src/main/jniLibs build --no-default-features --features native-audio
   ```
4. Open the Gradle project inside `android/` with Android Studio to run on a device or emulator.

## Project Structure

- `app/src/main/java` – Kotlin entry point that loads the Rust library via JNI.
- `app/src/main/res` – Placeholder resources. Replace with real assets and launch screens.
- `app/src/main/jniLibs` – Shared libraries produced by `cargo ndk`.

The Kotlin `MainActivity` delegates lifecycle events to Rust through JNI bindings defined in `app/src/main/java/com/example/vanillaebookreader/ReaderBridge.kt`. The Rust side exposes JNI-friendly functions (see `crates/ebook-reader/src/android.rs`) that call into `ebook_reader::run()`.

> **Note:** The scaffolding does not yet include a production-ready JNI bridge. Use this as a starting point and flesh out the JNI layer as you wire up the Slint Android backend.
