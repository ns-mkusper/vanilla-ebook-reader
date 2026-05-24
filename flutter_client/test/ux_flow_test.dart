import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_read_it/main.dart';
import 'package:just_read_it/services/document_repository.dart';
import 'package:just_read_it/services/tts_service.dart';

void main() {
  late Directory tempDir;
  late _RecordingSpeechService speech;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('just_read_it_ux_');
    speech = _RecordingSpeechService();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets(
      'AI paste flow is responsive, readable, and survives restart on mobile',
      (tester) async {
    _setSurface(tester, const Size(390, 844));
    await _pumpApp(tester, tempDir, speech);

    const geminiOutput =
        'AI draft: summarize this chapter, then read it aloud with focus.';
    final pasteTimer = Stopwatch()..start();
    await tester.enterText(find.byKey(const Key('editor.text')), geminiOutput);
    await tester.pump();
    pasteTimer.stop();

    expect(pasteTimer.elapsedMilliseconds, lessThan(300));
    expect(
        tester
            .widget<ElevatedButton>(find.byKey(const Key('player.launch')))
            .enabled,
        isTrue);

    await tester.tap(find.text('Read Aloud'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();

    expect(speech.lastText, geminiOutput);
    expect(find.text('Streaming Playback'), findsOneWidget);
    expect(find.byKey(const Key('player.highlight.label')), findsOneWidget);
    expect(find.byKey(const Key('player.highlight.rich_text')), findsOneWidget);

    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 100));
    await _pumpApp(tester, tempDir, speech);
    final restoredField = tester.widget<TextField>(
      find.byKey(const Key('editor.text')),
    );
    expect(restoredField.controller!.text, geminiOutput);
  });

  testWidgets('uses Motorola Male (Flite) as the default voice label',
      (tester) async {
    await _pumpApp(tester, tempDir, speech);
    expect(find.text('Motorola Male (Flite)'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('editor.text')), 'Voice check text.');
    await tester.pump();

    await tester.tap(find.text('Read Aloud'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();

    expect(speech.lastText, 'Voice check text.');
    expect(find.text('Classic voice: Motorola Male (Flite)'), findsOneWidget);
  });
}

void _setSurface(WidgetTester tester, Size logicalSize) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = logicalSize;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpApp(
  WidgetTester tester,
  Directory tempDir,
  _RecordingSpeechService speech,
) async {
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
  await tester.pump(const Duration(milliseconds: 100));
}

class _RecordingSpeechService implements SpeechService {
  String? lastText;

  @override
  Future<void> speak(String rawText) async {
    lastText = rawText;
  }
}
