import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/bridge_service.dart';
import 'ui/editor_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: TtsApp()));
  unawaited(
    initializeTtsBridge().catchError((Object err, StackTrace stack) {
      debugPrint('TTS bridge initialization failed: $err');
      debugPrintStack(stackTrace: stack);
    }),
  );
}

class TtsApp extends StatelessWidget {
  const TtsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Just Read It',
      theme: ThemeData.dark(),
      home: const EditorScreen(),
    );
  }
}
