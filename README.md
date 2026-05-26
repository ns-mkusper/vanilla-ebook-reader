# Just Read It

**Just Read It** is a Flutter + Rust read-aloud app for importing long-form text, editing it locally, and playing it back with synchronized word highlighting and native media controls.

The project is currently focused on Android. It ships a production-style mobile UI, persistent document storage, native file import, real synthesized audio playback, background/media controls, adjustable speech settings, and emulator-backed playback validation.

<p align="center">
  <img src="docs/assets/android-editor-import.png" alt="Just Read It editor showing imported text and reading controls" width="320" />
  <img src="docs/assets/android-player-playback.png" alt="Just Read It player showing synchronized highlighting and playback controls" width="320" />
</p>

## What it does

- **Import real documents**: TXT, Markdown, and EPUB import through the Android file browser / Storage Access Framework. Provider-backed files such as Google Drive documents are read from picker bytes instead of requiring filesystem paths.
- **Keep text editable**: imported or pasted content remains editable and persists across app restarts.
- **Read aloud with real playback**: generated speech is played through the app's native media pipeline rather than a fake timer or UI-only mock.
- **Highlight while listening**: word boundaries and playback progress drive synchronized highlighting in the reader view.
- **Control playback everywhere**: `audio_service` + `just_audio` provide foreground/background playback, pause/resume/stop, speed control, and Android media notification integration.
- **Tune the voice**: choose between embedded Flite and Android system TTS paths, then adjust rate and pitch.
- **Follow the system theme**: the app uses the platform light/dark preference by default.

## Architecture

```text
just-read-it/
├── flutter_client/         # Flutter app, Riverpod state, document import, UI, audio service
├── rust_core/              # Rust synthesis/audio core exposed through Flutter Rust Bridge
├── tools/                  # Validation and project automation scripts
└── docs/assets/            # README screenshots and visual assets
```

### Runtime pipeline

```text
Document picker / pasted text
        ↓
DocumentRepository
        ↓
Editable Flutter text surface
        ↓
TTS service: Android system TTS or embedded Rust/Flite path
        ↓
WAV/PCM audio source
        ↓
just_audio + audio_service
        ↓
Native playback, notification controls, word highlighting, exported test artifacts
```

## Current platform status

| Platform | Status | Notes |
| --- | --- | --- |
| Android | Active target | File browser import, background playback, media controls, emulator screenshots/audio validation. |
| iOS | Planned | Tracked in [issue #2](https://github.com/ns-mkusper/just-read-it/issues/2). Needs iOS bridge packaging, Files import validation, and background audio verification. |
| Desktop | Development-friendly | Useful for Flutter/Rust iteration, but mobile UX is the primary product target. |

## Key technical components

### Flutter client

- `flutter_client/lib/ui/editor_screen.dart` — editor, import entry point, persistent draft UI.
- `flutter_client/lib/ui/player_screen.dart` — playback screen, progress, highlighting, pause/stop controls.
- `flutter_client/lib/services/document_picker.dart` — native picker wrapper using `file_picker`.
- `flutter_client/lib/services/document_repository.dart` — TXT/Markdown/EPUB import, EPUB XHTML extraction, draft persistence.
- `flutter_client/lib/services/tts_service.dart` — speech synthesis orchestration, chunking, timeline attachment.
- `flutter_client/lib/services/audio_handler.dart` — native media playback, queueing, notification/media-session integration.

### Rust core

- `rust_core/` contains the Rust audio/synthesis bridge used by Flutter Rust Bridge.
- Embedded Flite support is built from upstream source at build time instead of vendoring the full Flite tree into this repository.
- Android builds produce `librust_core.so` under `flutter_client/android/app/src/main/jniLibs/<abi>/`.

## Build prerequisites

- Flutter stable with Android SDK/NDK configured.
- Rust stable.
- `cargo-ndk` for Android Rust library builds.
- `flutter_rust_bridge_codegen` matching the pinned Flutter/Rust bridge runtime.

```bash
cargo install cargo-ndk --locked
cargo install flutter_rust_bridge_codegen --version 2.11.1 --locked
```

## Bootstrap

```bash
cd flutter_client
flutter pub get
```

Regenerate Flutter ↔ Rust bindings when bridge APIs change:

```bash
flutter_rust_bridge_codegen generate
```

Or use the project helper when appropriate:

```bash
./tools/build_all.sh codegen
```

## Android build

Build the Rust shared library for Android ARM64:

```bash
cd rust_core
cargo ndk -t arm64-v8a \
  -o ../flutter_client/android/app/src/main/jniLibs \
  build --no-default-features --features bridge,flite
```

Build a debuggable APK:

```bash
cd ../flutter_client
flutter build apk --debug --target-platform android-arm64
```

The APK will be written to:

```text
flutter_client/build/app/outputs/flutter-apk/app-debug.apk
```

## Validation

Run the primary Flutter checks:

```bash
cd flutter_client
flutter analyze
flutter test
```

Run focused document/UI/TTS suites:

```bash
flutter test test/document_repository_test.dart
flutter test test/ux_flow_test.dart
flutter test test/tts_chunking_test.dart
flutter test test/performance/text_pipeline_perf_test.dart
```

Run Rust checks:

```bash
cd rust_core
cargo fmt --check
cargo clippy -- -D warnings
cargo test --no-default-features --features flite
cargo check --target aarch64-linux-android --no-default-features
```

Run the Android emulator screenshot/audio proof flow from `flutter_client/` when an emulator is available:

```bash
bash tool/android_screenshots.sh
```

That flow captures UI screenshots, exports playback WAV files, validates WAV structure, and checks speech output coverage.

## Import support

Supported extensions:

- `.txt`
- `.text`
- `.md`
- `.markdown`
- `.epub`

EPUB import extracts readable XHTML/HTML content from the archive and strips markup into plain text for editing and playback.

## Roadmap

- iOS compatibility and Files/iCloud import validation — [issue #2](https://github.com/ns-mkusper/just-read-it/issues/2).
- Stronger packaged release workflow beyond debug APK artifacts.
- More robust voice management and packaged voice metadata.
- Larger-library document management beyond the current active-draft workflow.

## License

Apache-2.0. See [LICENSE](LICENSE).
