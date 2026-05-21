import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_read_it/main.dart';
import 'package:just_read_it/services/document_repository.dart';
import 'package:just_read_it/services/tts_service.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('captures real app UI after PR interactions', (tester) async {
    final tempDir = await Directory.systemTemp.createTemp('just_read_it_e2e_');
    final speech = _IntegrationSpeechService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentDirectoryProvider.overrideWith((ref) async => tempDir),
          documentRepositoryProvider.overrideWithValue(
            DocumentRepository(directory: tempDir),
          ),
          ttsServiceProvider.overrideWithValue(speech),
        ],
        child: const TtsApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    await tester.enterText(
      find.byKey(const Key('editor.text')),
      'Screenshot fixture: a copyright-free sample paragraph ready to read aloud.',
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Read Aloud'), findsOneWidget);

    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 500));
    }
    await binding.takeScreenshot('01_editor_mobile');

    await tester.tap(find.text('Read Aloud'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(speech.lastText, contains('Screenshot fixture'));
    expect(find.text('Streaming Playback'), findsOneWidget);
    expect(find.byKey(const Key('player.highlight.rich_text')), findsOneWidget);
    await binding.takeScreenshot('02_player_mobile');
  });
}

class _IntegrationSpeechService implements SpeechService {
  String? lastText;

  @override
  Future<void> speak(String rawText) async {
    lastText = rawText;
  }
}
