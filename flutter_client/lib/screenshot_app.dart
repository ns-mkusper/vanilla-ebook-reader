import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'main.dart';
import 'services/document_repository.dart';
import 'services/tts_service.dart';

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

  runApp(
    ProviderScope(
      overrides: [
        documentDirectoryProvider.overrideWith((ref) async => directory),
        documentRepositoryProvider.overrideWithValue(repository),
        ttsServiceProvider.overrideWithValue(_ScreenshotSpeechService()),
      ],
      child: const TtsApp(),
    ),
  );
}

class _ScreenshotSpeechService implements SpeechService {
  @override
  Future<void> speak(String rawText) async {}
}
