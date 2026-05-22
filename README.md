# Just Read It

Just Read It is a no-nonsense Android text-to-speech app for turning ebooks and text files into readable, listenable playback. It pairs a Flutter UI with a Rust synthesis core so the app can read aloud while visually tracking text word by word.

Highlights:

- **Ebook and text-first workflow** – bring in long-form reading material, paste text, or dictate text and stream it immediately through the integrated player.
- **Graphical read-aloud experience** – follow along as each word is highlighted in sync with generated speech.
- **Background playback** – `audio_service`/`just_audio` keep narration active with Android foreground notifications and iOS `UIBackgroundModes = audio`.
- **Qwen-TTS voice presets** – choose from the latest Qwen-TTS voice names used by the app’s fast local synthesis preview path.
- **Persistent imports** – import TXT/EPUB content, keep the editable text between app restarts, and resume read-aloud quickly.

The repository is organized as a split Flutter/Rust workspace so engines, bindings, and UI can evolve independently.

## Layout

- `rust_core/`: Streaming synthesis backend with swappable engines (Piper-ready scaffolding today) exposed over Flutter Rust Bridge.
- `flutter_client/`: Flutter UI + background audio service integrating document import, Riverpod state, and the bridge bindings.
- `tools/`: Project automation (`build_all.sh`) plus local tool stubs to unblock codegen in containerized environments.

## Prerequisites

- Rust toolchain with `cargo ndk` for Android targets
- Flutter 3.19+ with the Android SDK/NDK configured
- `flutter_rust_bridge_codegen` on the host `PATH`:

  ```bash
  cargo install flutter_rust_bridge_codegen --locked
  ```


## Bootstrap

1. Install Flutter/Dart packages and copy the bundled Piper voice into the writable App Support directory (first run only):

   ```bash
   cd flutter_client
   flutter pub get
   ```

2. Regenerate the Flutter↔Rust bindings (the script now reads `flutter_rust_bridge.yaml`, so paths are normalized on Windows and the previous UNC prefix issue disappears):

   ```bash
   ./tools/build_all.sh codegen
   ```

3. Build the Rust core for the host platform:

   ```bash
   ./tools/build_all.sh rust
   ```

   > The script passes `--features bridge,piper` so the Piper engine and FFI stubs are always available. For Android shared libraries run `./tools/build_all.sh android` – `cargo ndk` will place the `.so` files under `flutter_client/android/app/src/main/jniLibs`.

4. Build and launch Flutter:

   ```bash
   cd flutter_client
   flutter run
   ```

   To generate a debuggable APK that can be side-loaded on an emulator or device:

   ```bash
   flutter build apk --debug
   ```

## Voice Models

- **Qwen-TTS presets**: The UI exposes Qwen-TTS latest voice presets (Cherry, Ethan, Chelsie, Serena, Dylan, Jada, and Sunny) for the read-aloud workflow. The current offline preview engine validates the app pipeline without network credentials.
- **Background playback**: Android ships the `com.ryanheise.audioservice.AudioService` foreground service plus the required `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permission, while iOS has `UIBackgroundModes = audio`. Nothing else is needed—`AudioServiceConfig` already advertises the persistent notification on Android and `just_audio` keeps the shared session alive on iOS.

## Tooling

`tools/build_all.sh` now orchestrates:

- `flutter_rust_bridge_codegen --config flutter_rust_bridge.yaml`
- `cargo build --features bridge,piper`
- `cargo ndk` / `cargo lipo` for mobile targets
- `flutter build apk` when requested

Because the generator reads the YAML config, Windows paths are normalized and the previous `compute_mod_from_rust_path` “prefix not found” panic is resolved.

## Performance Guardrails

Keep both the Rust core and the Flutter text pipeline from regressing by running the dedicated performance suites:

```bash
# Bench the Rust synthesis primitives (requires a longer first build)
cargo bench --bench engine_bench

# Enforce Dart-side timing thresholds for boundary + cue generation
cd flutter_client
flutter test test/performance/text_pipeline_perf_test.dart
```

`cargo bench` emits Criterion HTML reports under `target/criterion/`. Inspect the generated plot if a run flags a regression. The Flutter suite fails whenever a 4k-word sample exceeds its microsecond budget, which keeps boundary detection, cue building, and highlighting lookups near-linear.
