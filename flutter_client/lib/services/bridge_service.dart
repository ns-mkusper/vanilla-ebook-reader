import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:just_read_it/api.dart' as bridge;
import 'package:just_read_it/frb_generated.dart';

bool _bridgeInitialized = false;
Future<void>? _bridgeInitFuture;

Future<void> initializeTtsBridge() {
  if (_bridgeInitialized) {
    return Future<void>.value();
  }
  return _bridgeInitFuture ??= _initializeTtsBridgeImpl();
}

Future<void> _initializeTtsBridgeImpl() async {
  if (kIsWeb) {
    throw UnsupportedError('Web is not yet supported for the TTS engine');
  }

  final library = _resolveExternalLibrary();
  await TtsBridge.init(externalLibrary: library);
  const rustLogFilter = String.fromEnvironment('RUST_LOG', defaultValue: '');
  await bridge.initTracing(
    filter: rustLogFilter.isEmpty ? null : rustLogFilter,
  );
  await bridge.bootstrapDefaultEngine();
  _bridgeInitialized = true;
}

ExternalLibrary _resolveExternalLibrary() {
  if (Platform.isIOS) {
    return ExternalLibrary.process(iKnowHowToUseIt: true);
  }

  final name = _libraryFileName();
  final workspaceLib = File('${Directory.current.path}/target/debug/$name');
  if (workspaceLib.existsSync()) {
    return ExternalLibrary.open(workspaceLib.path);
  }
  return ExternalLibrary.open(name);
}

String _libraryFileName() {
  if (Platform.isAndroid || Platform.isLinux) {
    return 'librust_core.so';
  }
  if (Platform.isIOS) {
    // The iOS Xcode target statically links librust_core.a from the
    // Build Rust Core phase. Static iOS FFI symbols are resolved from the
    // process image instead of a dlopen-able framework.
    return '';
  }
  if (Platform.isMacOS) {
    return 'librust_core.dylib';
  }
  if (Platform.isWindows) {
    return 'rust_core.dll';
  }
  return 'librust_core.so';
}
