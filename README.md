# Vanilla Ebook Reader

Vanilla Ebook Reader is a cross-platform reading app that keeps your audiobooks and ebooks in one polished library. It blends a clean Slint interface with seamless playback so you can jump between listening and reading without losing your place.

## What you can do
- **Mix formats in one shelf**: import titles that include EPUB, PDF, MOBI, or chaptered audio and browse them side by side.
- **Stay perfectly in sync**: progress updates flow between text and audio, so you can swap devices or switch modes mid-chapter.
- **Listen your way**: enjoy gapless playback, remembered speed settings, and quick chapter scrubbing.
- **Read comfortably**: turn pages with keyboard, touch, or mouse; adjust typography, theme, and layout to fit the moment.
- **Search and organize**: scan folders for new books, surface metadata-rich details, and filter by narrator, series, or completion status.
- **Take it everywhere**: the same UI runs on desktop today and is ready for Android builds, keeping features consistent across platforms.

## Getting started
1. Install the stable Rust toolchain (`rustup default stable`).
2. Place your library under `assets/library/` following the sample book structure, or point `VANILLA_READER_LIBRARY_ROOT` to your collection.
3. Launch the reader on desktop:
   ```bash
   cargo run -p ebook-reader --features native-audio -- assets/library/sample
   ```
   If system audio headers are missing, drop `--features native-audio` to explore the UI with a silent backend.

Want it on Android? Use `cargo ndk` to build the shared library, then open `android/` in Android Studio or run `./gradlew assembleDebug` to produce an APK.

## Roadmap at a glance
- Cloud library sync across devices.
- Annotation export and highlight sharing.
- Built-in audiobook sleep timer and smart bookmark cues.
- Localization with community-driven translations.

## License
Dual-licensed under MIT or Apache-2.0.
