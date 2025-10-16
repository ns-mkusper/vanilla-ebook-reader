# Vanilla Ebook Reader

Vanilla Ebook Reader is a cross-platform reading app that keeps your audiobooks and ebooks in one polished library. It blends a clean Slint interface with seamless playback so you can jump between listening and reading without losing your place.

## What you can do
- **Mix formats in one shelf**: drop folders of MP3, WAV, EPUB, MOBI, PDF, Markdown, or plain text and the library indexes them automatically—no JSON metadata required.
- **Open text instantly**: the built-in reader renders EPUB/MOBI chapters, extracts PDF pages, and prettifies HTML or Markdown so you can read even when there’s no audio track.
- **Listen your way**: enjoy gapless playback, remembered speed settings, and quick chapter scrubbing for any folder of chaptered audio.
- **Stay perfectly in sync**: progress updates flow between text and audio, so you can swap devices or switch modes mid-chapter.
- **Take it everywhere**: the same UI runs on desktop today and is ready for Android builds, keeping features consistent across platforms.

## Getting started
1. Install the stable Rust toolchain (`rustup default stable`).
2. Point `VANILLA_READER_LIBRARY_ROOT` at a directory that contains your books (each top-level folder or standalone file becomes a library entry). The legacy `book.json` flow still works if you prefer curated metadata.
3. Launch the reader on desktop:
   ```bash
   cargo run -p ebook-reader --features native-audio -- assets/library/sample
   ```
   If your system is missing audio development headers, drop `--features native-audio` to explore the UI with a silent backend.

Want it on Android? Use `cargo ndk` to build the shared library (include `--features native-audio` now that Rodio works via CPAL on Android), then open `android/` in Android Studio or run `./gradlew assembleDebug` to produce an APK.

## Roadmap at a glance
- Cloud library sync across devices.
- Annotation export and highlight sharing.
- Built-in audiobook sleep timer and smart bookmark cues.
- Localization with community-driven translations.

## License
Dual-licensed under MIT or Apache-2.0.
