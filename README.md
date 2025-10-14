# Vanilla Ebook Reader

Vanilla Ebook Reader is a cross-platform E-Book reader that brings together library indexing, audio playback, and a Slint-based interface. The goal is a cross-platform reader that can handle both narrated audiobooks and traditional ebooks while sharing as much UI code as possible across Android, desktop, and future targets.

### Highlights
- **Unified media model** – every entry can include audio chapters, rich text sources (EPUB, MOBI/PDF), or both.
- **Slint front end** – renders a native-feeling UI on desktop today and Android via the Slint activity backend.
- **Async playback core** – `ebook-core` exposes a clean API for queueing audio chapters and reporting progress, making it easy to swap backends.
- **Android scaffolding** – Kotlin stubs plus a JNI bridge are ready to launch the Rust UI inside an Android app package.

### Repository layout
```
.
├── Cargo.toml                # Workspace definition and shared deps
├── assets/                   # Sample metadata, audio stubs, and text placeholders
├── android/                  # Gradle project, JNI entry points, resources
├── crates/
│   ├── ebook-core/           # Library scanning, text parsing, playback state machine
│   └── ebook-reader/         # Slint UI crate with Rodio-backed audio runtime
└── .github/workflows/ci.yml  # Formatting, clippy, host build, android cross-check
```

### Quick start on desktop
1. Install the stable Rust toolchain (`rustup default stable`).
2. Verify dependencies: `cargo check`.
3. Drop media into `assets/library/<title>/book.json`. The sample directory shows how to describe audio chapters and an EPUB source.
4. Launch the reader:
   ```bash
   cargo run -p ebook-reader --features native-audio -- assets/library/sample
   ```
   Skip `--features native-audio` if system audio headers are missing; the UI will still load with the null backend.

`VANILLA_READER_LIBRARY_ROOT` can be set to point the app at a different library path when running locally or packaging builds.

### Android build notes
- `ebook-reader` compiles as a `cdylib`; `android/app` loads `libebook_reader.so` via `ReaderBridge`.
- Build the shared library with `cargo ndk` (install via `cargo install cargo-ndk`):
  ```bash
  cargo ndk -t arm64-v8a -o android/app/src/main/jniLibs build --no-default-features --features native-audio
  ```
- Open `android/` in Android Studio or run `./gradlew assembleDebug`. The JNI shim currently boots the Slint window; extend it as you integrate lifecycle or text rendering behaviour.

### Continuous integration
The GitHub Actions workflow runs `cargo fmt`, `cargo clippy -- -D warnings`, a host `cargo check`, and an `aarch64-linux-android` cross-check with `SLINT_NO_QT=1` to keep builds deterministic.

### License
Dual-licensed under MIT or Apache-2.0.
