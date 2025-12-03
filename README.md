# High-Performance TTS Beast

This repository hosts a split Flutter/Rust stack for a streaming text-to-speech experience. The Rust core exposes synthesis primitives and timing metadata through Flutter Rust Bridge, while the Flutter client delivers a GenUI-driven interface with background audio support.

## Layout

- `rust_core/`: Streaming synthesis backend with swappable engines (Piper-ready scaffolding today) exposed over Flutter Rust Bridge.
- `flutter_client/`: Flutter UI + background audio service integrating GenUI-driven configuration, Riverpod state, and the bridge bindings.
- `tools/`: Project automation (`build_all.sh`) plus local tool stubs to unblock codegen in containerized environments.

## Bootstrap

1. Generate bridge bindings and supporting Dart artifacts:

   ```bash
   tools/build_all.sh codegen
   ```

   > The repo ships with a minimal `flutter_client/lib/api.freezed.dart` stub so analysis works without Flutter. Once the Flutter toolchain is available, run `flutter pub run build_runner build` to regenerate the `freezed` output properly.

2. Build the Rust dynamic library (desktop debug example):

   ```bash
   (cd rust_core && cargo build --features bridge)
   ```

3. Point Flutter at the compiled library (desktop defaults look in `target/debug/` via `_resolveExternalLibrary()` in `lib/main.dart`). Android/iOS builds are orchestrated by `tools/build_all.sh android|ios`.

4. Launch Flutter (after installing the Flutter SDK):

   ```bash
   cd flutter_client
   flutter pub get
   flutter run
   ```

## Tooling

Refer to `tools/build_all.sh` for an overview of the multi-platform build pipeline. The script wraps `flutter_rust_bridge_codegen`, `cargo ndk`, `cargo lipo`, and Flutter build targets so that a single entry point can regenerate bindings and artifacts for every target.
