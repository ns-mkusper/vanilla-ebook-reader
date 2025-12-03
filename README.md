# Vanilla Ebook Reader

Vanilla Ebook Reader is a text-to-speech controller for Android and iOS built from Flutter UI layers and a Rust synthesis core. Highlights:

- **Paste-and-play workflow** – enter arbitrary text and stream it immediately through the integrated player.
- **Voice and LLM controls** – select between the bundled Piper preset or procedural mock voice, and drive UI tuning via GenUI + Gemini models.
- **Word-level highlighting** – the Rust backend emits chunk indices so the Flutter client highlights each word in sync.
- **Background audio compliance** – `audio_service`/`just_audio` keep playback active with Android foreground notifications and iOS `UIBackgroundModes = audio`.
- **Offline voice asset** – the low-tier `en_us_amy_low` Piper model is packaged under `assets/`, ensuring speech synthesis without network access.

The repository is organized as a split Flutter/Rust workspace so engines, bindings, and UI can evolve independently.

## Layout

- `rust_core/`: Streaming synthesis backend with swappable engines (Piper-ready scaffolding today) exposed over Flutter Rust Bridge.
- `flutter_client/`: Flutter UI + background audio service integrating GenUI-driven configuration, Riverpod state, and the bridge bindings.
- `tools/`: Project automation (`build_all.sh`) plus local tool stubs to unblock codegen in containerized environments.

## Prerequisites

- Rust toolchain with `cargo ndk` for Android targets
- Flutter 3.19+ with the Android SDK/NDK configured
- `flutter_rust_bridge_codegen` on the host `PATH`:

  ```bash
  cargo install flutter_rust_bridge_codegen --locked
  ```

- (Optional) Gemini access key for GenUI orchestration:

  ```bash
  flutter run --dart-define=GENAI_API_KEY=your_key
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

## GenUI & Voice Models

- **GenUI SDK**: The configuration drawer (robot icon) is powered by `genui` + `genui_google_generative_ai`. Provide a Gemini key through `--dart-define=GENAI_API_KEY=...` to let the agent call `updateTtsPreferences`; otherwise it runs in offline echo mode.
- **LLM selection**: The editor exposes a dropdown for the GenUI LLM. Internally the selection is fed into the agent provider so Gemini requests honor the chosen model.
- **Traditional TTS**: Selecting the “Amy (en-US)” preset copies the bundled Piper `.onnx`/`.json` pair (`en_us_amy_low`) into `ApplicationSupportDirectory/voices/amy-low`. The low-tier model boots quickly, and the Rust core feeds it through `piper-rs` + ONNX Runtime, streaming PCM back to Flutter along with per-chunk indices for word highlighting.
- **LLM vs. Procedural**: A mock “Orbit” voice remains available for instant previews without the ONNX runtime.
- **Background playback**: Android ships the `com.ryanheise.audioservice.AudioService` foreground service plus the required `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permission, while iOS has `UIBackgroundModes = audio`. Nothing else is needed—`AudioServiceConfig` already advertises the persistent notification on Android and `just_audio` keeps the shared session alive on iOS.

## Tooling

`tools/build_all.sh` now orchestrates:

- `flutter_rust_bridge_codegen --config flutter_rust_bridge.yaml`
- `cargo build --features bridge,piper`
- `cargo ndk` / `cargo lipo` for mobile targets
- `flutter build apk` when requested

Because the generator reads the YAML config, Windows paths are normalized and the previous `compute_mod_from_rust_path` “prefix not found” panic is resolved.

## Tooling

Refer to `tools/build_all.sh` for an overview of the multi-platform build pipeline. The script wraps `flutter_rust_bridge_codegen`, `cargo ndk`, `cargo lipo`, and Flutter build targets so that a single entry point can regenerate bindings and artifacts for every target.

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
