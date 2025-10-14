# Vanilla Ebook Reader

A Rust-first ebook reader scaffold targeting Android first, with paths to desktop (Windows, macOS, Linux), iOS, and the web. The UI is implemented with [Slint](https://slint.dev) so one declarative view layer renders across platforms, while the core library/indexing logic lives in a reusable crate.

## Layout

```
.
├── Cargo.toml                # Workspace definition
├── assets/                   # Sample metadata & placeholders
├── android/                  # Gradle project skeleton for JNI + packaging
├── crates/
│   ├── ebook-core/           # Domain logic: library scanning, playback state, traits
│   └── ebook-reader/         # Slint UI, audio backend, desktop & mobile entry points
└── .github/workflows/ci.yml  # GitHub Actions pipeline
```

## Getting Started (Desktop)

1. Install the latest stable Rust toolchain (`rustup default stable`).
2. Fetch dependencies and ensure the workspace compiles:
   ```bash
   cargo check
   ```
3. Add your media under `assets/library/<book>/` and update `book.json` (a placeholder lives under `assets/library/sample`).
4. Run the desktop app:
   ```bash
   cargo run -p ebook-reader --features native-audio -- assets/library/sample
   ```
   Omit `--features native-audio` if system audio headers are unavailable; the UI will still launch with the no-op backend.

Environment variables:
- `VANILLA_READER_LIBRARY_ROOT` – override the library path without providing a CLI argument.

## Android Notes

- The Rust UI crate exports a `cdylib` so it can be loaded from the Android layer.
- The `android/` directory ships a minimal Compose `MainActivity` stub and JNI bridge that expects a `libebook_reader.so` artefact.
- Build the shared library with `cargo ndk` (install via `cargo install cargo-ndk`):
  ```bash
  cargo ndk -t arm64-v8a -o android/app/src/main/jniLibs build --no-default-features --features native-audio
  ```
- Open the Gradle project in Android Studio or run `./gradlew assembleDebug` inside `android/` once the NDK paths are configured (`ANDROID_HOME`, `ANDROID_NDK_HOME`).

> The JNI surface is intentionally minimal; extend `ReaderBridge.kt` and add Rust functions mirroring the Android lifecycle as you wire up the Slint Android backend.

## Continuous Integration

GitHub Actions run formatting, clippy, host checks, and a cross-compilation sanity check for `aarch64-linux-android`. All jobs set `SLINT_NO_QT=1` so the Qt backend is skipped during CI.

## Next Steps

- Flesh out the JNI bridge (`android` → Rust) and hook into the Slint Android renderer.
- Persist reading/listening progress and library metadata (e.g. `sled` or `sqlite` store).
- Integrate platform media/notification controls on Android.
- Expand the library scanner to index OPF/JSON metadata exports from ebook managers.
- Explore web & desktop builds via WebAssembly or Tauri once the core stabilises.

## License

Dual-licensed under MIT or Apache-2.0.
