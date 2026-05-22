import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'main.dart' as app;
import 'services/document_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory =
      await Directory.systemTemp.createTemp('just_read_it_shots_');
  final repository = DocumentRepository(directory: directory);
  await repository.saveDraft(
    const ReaderDocument(
      title: 'Screenshot fixture',
      text:
          'Screenshot fixture: a copyright-free sample paragraph ready to read aloud.',
    ),
  );

  await app.initializeTtsBridge();
  runApp(
    ProviderScope(
      overrides: [
        documentDirectoryProvider.overrideWith((ref) async => directory),
        documentRepositoryProvider.overrideWithValue(repository),
      ],
      child: const app.TtsApp(),
    ),
  );

  Timer(const Duration(seconds: 2), () {
    // The Android screenshot workflow waits for this before capturing, so it
    // does not grab the native launch/splash screen.
    // ignore: avoid_print
    print('JRI_SCREENSHOT_READY');
  });
}
