# Just Read It

**Just Read It** is a Flutter + Rust read-aloud app for importing long-form text, editing it locally, and playing it back with synchronized word highlighting and native media controls.

The project is currently focused on Android. It ships a production-style mobile UI, persistent document storage, native file import, real synthesized audio playback, background/media controls, adjustable speech settings, and emulator-backed playback validation.

<p align="center">
  <img src="docs/assets/android-editor-import.png" alt="Just Read It editor showing imported text and reading controls" width="320" />
  <img src="docs/assets/android-player-playback.png" alt="Just Read It player showing synchronized highlighting and playback controls" width="320" />
</p>

## Architecture

```text
just-read-it/
├── flutter_client/         # Flutter app, Riverpod state, document import, UI, audio service
├── rust_core/              # Rust synthesis/audio core exposed through Flutter Rust Bridge
├── tools/                  # Validation and project automation scripts
└── docs/                   # Architecture, validation, roadmap, and README assets
```

Further technical notes:

- [Runtime pipeline](docs/runtime-pipeline.md)
- [Validation guide](docs/validation.md)
- [Release workflow](docs/releases.md)
- [Roadmap](docs/roadmap.md)

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

## Import support

Supported extensions:

- `.txt`
- `.text`
- `.md`
- `.markdown`
- `.epub`

EPUB import extracts readable XHTML/HTML content from the archive and strips markup into plain text for editing and playback.

## License

Apache-2.0. See [LICENSE](LICENSE).
