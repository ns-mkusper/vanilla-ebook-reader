import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:tts_flutter_client/api.dart' as bridge;
import 'package:tts_flutter_client/frb_generated.dart';

import 'ui/editor_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeRustBridge();
  runApp(const ProviderScope(child: TtsApp()));
}

class TtsApp extends StatelessWidget {
  const TtsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TTS Beast',
      theme: ThemeData.dark(),
      home: const EditorScreen(),
    );
  }
}

Future<void> _initializeRustBridge() async {
  if (kIsWeb) {
    throw UnsupportedError('Web is not yet supported for the TTS engine');
  }

  final library = _resolveExternalLibrary();
  await TtsBridge.init(externalLibrary: library);
  await bridge.bootstrapDefaultEngine();
}

ExternalLibrary _resolveExternalLibrary() {
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
    return 'rust_core.framework/rust_core';
  }
  if (Platform.isMacOS) {
    return 'librust_core.dylib';
  }
  if (Platform.isWindows) {
    return 'rust_core.dll';
  }
  return 'librust_core.so';
}
