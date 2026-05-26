# Roadmap

This roadmap is intentionally practical: prioritize real document import, reliable native playback, and mobile polish before expanding into larger library-management or multi-platform features.

## Near term

### Android UX hardening

- Continue stabilizing the native file-browser import path for TXT, Markdown, and EPUB.
- Keep Google Drive / content-provider imports pathless and byte-based where possible.
- Improve empty/error states for unsupported files and unreadable EPUB archives.
- Keep screenshot and audio artifact validation part of every PR that touches playback, import, or layout.

### Release workflow

- Add a cleaner release build path beyond debug APK artifacts.
- Document signing requirements and local release commands.
- Separate CI proof artifacts from user-facing release artifacts.

### Voice and playback quality

- Keep embedded Flite as the default offline path while preserving Android system TTS as a fallback/test path.
- Add clearer voice metadata and user-facing voice descriptions.
- Improve long-document chunk queue behavior and progress reporting.
- Preserve native media controls and background playback as non-negotiable acceptance criteria.

## iOS compatibility

Tracked in [issue #2](https://github.com/ns-mkusper/just-read-it/issues/2).

Target scope:

- build and run the Flutter client on iOS simulators and physical devices;
- package the Rust bridge correctly for iOS targets;
- validate Files/iCloud Drive document import;
- define the iOS voice backend strategy;
- configure background audio and lock-screen controls;
- add documented validation for launch, import, playback, highlighting, and media controls.

## Medium term

### Document library

- Move beyond a single active draft into a lightweight local library.
- Track source filename, import time, document title, and reading progress.
- Add rename/delete/re-import flows without complicating the core editor.

### EPUB improvements

- Respect spine order instead of relying only on sorted readable entries.
- Improve table-of-contents handling.
- Preserve chapter boundaries in imported plain text.

### Accessibility and polish

- Audit screen-reader labels and tap targets.
- Add better large-font behavior for editor and player views.
- Improve landscape/tablet layouts.

## Long term

- Explore optional downloadable neural voices if size, licensing, and mobile performance are acceptable.
- Add richer highlighting modes, bookmarks, and chapter navigation.
- Consider desktop packaging only after mobile flows are stable and documented.
