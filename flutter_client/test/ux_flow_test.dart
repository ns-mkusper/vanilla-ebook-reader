import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_read_it/main.dart';
import 'package:just_read_it/services/audio_handler.dart';
import 'package:just_read_it/services/document_picker.dart';
import 'package:just_read_it/services/document_repository.dart';
import 'package:just_read_it/services/tts_preferences_repository.dart';
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
    expect(find.byKey(const Key('playback.speed')), findsNothing);
    expect(find.byKey(const Key('voice.pitch')), findsNothing);

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
    expect(find.byKey(const Key('player.seekbar')), findsOneWidget);
    expect(find.byKey(const Key('playback.speed')), findsOneWidget);
    expect(find.byKey(const Key('voice.pitch')), findsOneWidget);
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
    expect(find.text('Streaming Playback'), findsOneWidget);
  });

  testWidgets('pause button shows play after it is pressed', (tester) async {
    await _pumpApp(
      tester,
      tempDir,
      speech,
      audioHandler: TtsAudioHandler(player: _FakeAudioPlayerController()),
    );
    await tester.enterText(
      find.byKey(const Key('editor.text')),
      'Pause button label check.',
    );
    await tester.pump();
    await tester.tap(find.text('Read Aloud'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();

    expect(find.text('Pause'), findsOneWidget);

    await tester.tap(find.byKey(const Key('player.pause')));
    await tester.pump();

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);
  });

  testWidgets('stop button changes primary playback control back to play',
      (tester) async {
    await _pumpApp(
      tester,
      tempDir,
      speech,
      audioHandler: TtsAudioHandler(player: _FakeAudioPlayerController()),
    );
    await tester.enterText(
      find.byKey(const Key('editor.text')),
      'Stop button label check.',
    );
    await tester.pump();
    await tester.tap(find.text('Read Aloud'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();

    expect(find.text('Pause'), findsOneWidget);

    await tester.tap(find.byKey(const Key('player.stop')));
    await tester.pump();

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);
    expect(find.text('Stopped'), findsOneWidget);
  });

  testWidgets('changing playback speed updates the active audio player',
      (tester) async {
    final player = _FakeAudioPlayerController();
    await _pumpApp(
      tester,
      tempDir,
      speech,
      audioHandler: TtsAudioHandler(player: player),
    );
    await tester.enterText(
      find.byKey(const Key('editor.text')),
      'Live speed change check.',
    );
    await tester.pump();
    await tester.tap(find.text('Read Aloud'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();

    await _selectDropdownValue(tester, const Key('playback.speed'), '1.50×');

    expect(player.speedChanges, contains(1.5));
  });

  testWidgets('changing pitch restarts active playback with the same text',
      (tester) async {
    await _pumpApp(
      tester,
      tempDir,
      speech,
      audioHandler: TtsAudioHandler(player: _FakeAudioPlayerController()),
    );
    await tester.enterText(
      find.byKey(const Key('editor.text')),
      'Live pitch change check.',
    );
    await tester.pump();
    await tester.tap(find.text('Read Aloud'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();

    expect(speech.calls, 1);

    await _selectDropdownValue(tester, const Key('voice.pitch'), '1.20×');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();

    expect(speech.calls, 2);
    expect(speech.lastText, 'Live pitch change check.');
  });

  testWidgets('playback controls use dropdowns on the player screen',
      (tester) async {
    await _pumpApp(tester, tempDir, speech);
    expect(find.byKey(const Key('playback.speed')), findsNothing);
    expect(find.byKey(const Key('voice.pitch')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('editor.text')),
      'Preference dropdown check.',
    );
    await tester.pump();
    await tester.tap(find.text('Read Aloud'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();

    expect(find.text('Streaming Playback'), findsOneWidget);
    expect(find.byKey(const Key('playback.speed')), findsOneWidget);
    expect(find.byKey(const Key('voice.pitch')), findsOneWidget);
    expect(find.byType(Slider), findsNothing);

    await _selectDropdownValue(tester, const Key('playback.speed'), '1.50×');
    await _selectDropdownValue(tester, const Key('voice.pitch'), '1.20×');

    final container =
        ProviderScope.containerOf(tester.element(find.byType(TtsApp)));
    expect(container.read(ttsConfigProvider).rate, 1.5);
    expect(container.read(ttsConfigProvider).pitch, 1.2);
  });

  testWidgets('imports picked markdown bytes from file browser without a path',
      (tester) async {
    final picker = _FakeDocumentPicker(
      PickedDocumentFile(
        name: 'drive_note.md',
        bytes: Uint8List.fromList(
          utf8.encode('# Drive note\nFile browser import fixture.'),
        ),
      ),
    );
    final repository = _ImmediateDocumentRepository(directory: tempDir);
    await _pumpApp(
      tester,
      tempDir,
      speech,
      picker: picker,
      repository: repository,
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('document.import')));
    await tester.tap(find.byKey(const Key('document.import')));
    expect(picker.calls, 1);
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final editor =
        tester.widget<TextField>(find.byKey(const Key('editor.text')));
    expect(editor.controller!.text, contains('File browser import fixture.'));
    expect(find.textContaining('Imported drive_note'), findsOneWidget);

    expect(repository.importedDocument?.sourcePath, isNull);
  });
}

Future<void> _selectDropdownValue(
  WidgetTester tester,
  Key dropdownKey,
  String label,
) async {
  await tester.tap(find.byKey(dropdownKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
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
  _RecordingSpeechService speech, {
  DocumentPicker? picker,
  DocumentRepository? repository,
  TtsAudioHandler? audioHandler,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        documentDirectoryProvider.overrideWith((ref) async => tempDir),
        documentRepositoryProvider.overrideWithValue(
          repository ?? DocumentRepository(directory: tempDir),
        ),
        ttsPreferencesRepositoryProvider.overrideWithValue(
          TtsPreferencesRepository(directory: tempDir),
        ),
        ttsServiceProvider.overrideWithValue(speech),
        audioHandlerProvider.overrideWithValue(
          Future.value(
            audioHandler ??
                TtsAudioHandler(player: _FakeAudioPlayerController()),
          ),
        ),
        documentPickerProvider.overrideWithValue(
          picker ?? _FakeDocumentPicker(null),
        ),
      ],
      child: const TtsApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

class _FakeAudioPlayerController implements AudioPlayerController {
  final speedChanges = <double>[];
  var playingValue = true;
  @override
  Stream<PlaybackEvent> get playbackEventStream =>
      const Stream<PlaybackEvent>.empty();

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<int?> get currentIndexStream => const Stream<int?>.empty();

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Duration get position => Duration.zero;

  @override
  Duration get bufferedPosition => Duration.zero;

  @override
  int? get currentIndex => 0;

  @override
  bool get playing => playingValue;

  @override
  double get speed => speedChanges.isEmpty ? 1.0 : speedChanges.last;

  @override
  ProcessingState get processingState => ProcessingState.ready;

  @override
  Future<void> play() async {
    playingValue = true;
  }

  @override
  Future<void> pause() async {
    playingValue = false;
  }

  @override
  Future<void> stop() async {
    playingValue = false;
  }

  @override
  Future<void> setSpeed(double speed) async {
    speedChanges.add(speed);
  }

  @override
  Future<void> setAudioSource(AudioSource source) async {}

  @override
  Future<void> seek(Duration position, {int? index}) async {}
}

class _RecordingSpeechService implements SpeechService {
  String? lastText;
  var calls = 0;

  @override
  Future<void> speak(String rawText) async {
    calls += 1;
    lastText = rawText;
  }
}

class _ImmediateDocumentRepository extends DocumentRepository {
  _ImmediateDocumentRepository({required super.directory});

  ReaderDocument? importedDocument;

  @override
  Future<ReaderDocument> importBytes({
    required String name,
    required Uint8List bytes,
    String? sourcePath,
  }) async {
    importedDocument = ReaderDocument(
      title: name.replaceFirst(RegExp(r'\.[^.]*$'), ''),
      text: utf8.decode(bytes, allowMalformed: true),
      sourcePath: sourcePath,
    );
    return importedDocument!;
  }
}

class _FakeDocumentPicker implements DocumentPicker {
  _FakeDocumentPicker(this.file);

  final PickedDocumentFile? file;
  var calls = 0;

  @override
  Future<PickedDocumentFile?> pickReadableDocument() async {
    calls += 1;
    return file;
  }
}
