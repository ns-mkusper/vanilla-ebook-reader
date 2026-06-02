import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_read_it/services/audio_handler.dart';
import 'package:just_read_it/services/text_analysis.dart';
import 'package:just_read_it/services/tts_service.dart';
import 'package:just_read_it/ui/player_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('word taps seek and update current highlighted word on emulator',
      (tester) async {
    const text =
        'Alpha bravo charlie delta echo foxtrot golf hotel india juliet.';
    final speech = _ControllableSpeechService();
    final audioHandler = TtsAudioHandler(player: _FakeAudioPlayerController());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ttsServiceProvider.overrideWith((ref) => speech.bind(ref)),
          audioHandlerProvider.overrideWithValue(Future.value(audioHandler)),
        ],
        child: const MaterialApp(home: PlayerScreen(text: text)),
      ),
    );

    await _pumpUntilFound(
      tester,
      find.byKey(const Key('player.highlight.rich_text')),
      timeout: const Duration(seconds: 10),
    );
    expect(speech.lastSpokenText, text);

    _expectCurrentWord(tester, 'Alpha');
    _expectHighlightedWord(tester, 'Alpha');

    await _tapWord(tester, text, 'echo');
    await tester.pumpAndSettle();
    expect(speech.seekRequests, contains(4));
    _expectCurrentWord(tester, 'echo');
    _expectHighlightedWord(tester, 'echo');

    await _tapWord(tester, text, 'juliet.');
    await tester.pumpAndSettle();
    expect(speech.seekRequests, contains(9));
    _expectCurrentWord(tester, 'juliet.');
    _expectHighlightedWord(tester, 'juliet.');

    await _tapWord(tester, text, 'bravo');
    await tester.pumpAndSettle();
    expect(speech.seekRequests, contains(1));
    _expectCurrentWord(tester, 'bravo');
    _expectHighlightedWord(tester, 'bravo');

    debugPrint(
      'JRI_WORD_SEEK_HIGHLIGHT_VALIDATED seeks=${speech.seekRequests.join(',')}',
    );
  });
}

Future<void> _tapWord(WidgetTester tester, String text, String word) async {
  final boundaries = computeWordBoundaries(text);
  final boundary = boundaries.singleWhere(
    (boundary) => text.substring(boundary.start, boundary.end) == word,
  );
  final paragraph = tester.renderObject<RenderParagraph>(
    find.byKey(const Key('player.highlight.rich_text')),
  );
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: boundary.start, extentOffset: boundary.end),
  );
  expect(boxes, isNotEmpty, reason: 'Expected word "$word" to be laid out.');
  final localCenter = boxes.first.toRect().center;
  await tester.tapAt(paragraph.localToGlobal(localCenter));
}

void _expectCurrentWord(WidgetTester tester, String word) {
  expect(
    tester.widget<Text>(find.byKey(const Key('player.current_word'))).data,
    'Reading: $word',
  );
}

void _expectHighlightedWord(WidgetTester tester, String word) {
  final richText = tester.widget<RichText>(
    find.byKey(const Key('player.highlight.rich_text')),
  );
  final activeWords = <String>[];
  _collectHighlightedWords(richText.text, activeWords);
  expect(activeWords, [word]);
}

void _collectHighlightedWords(InlineSpan span, List<String> activeWords) {
  if (span is TextSpan) {
    if (span.style?.backgroundColor != null && span.text != null) {
      activeWords.add(span.text!);
    }
    final children = span.children;
    if (children != null) {
      for (final child in children) {
        _collectHighlightedWords(child, activeWords);
      }
    }
  }
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

class _ControllableSpeechService implements SpeechService {
  _ControllableSpeechService();

  Ref? _ref;
  String? lastSpokenText;
  final seekRequests = <int>[];

  @override
  Future<void> speak(String rawText) async {
    lastSpokenText = rawText;
    final ref = _ref;
    if (ref == null) return;
    final boundaries = computeWordBoundaries(rawText);
    ref.read(wordBoundariesProvider.notifier).state = boundaries;
    ref.read(wordChunkOffsetsProvider.notifier).state = const [0];
    ref.read(wordChunkWordCountsProvider.notifier).state = [boundaries.length];
    ref.read(wordTimelineFallbackDurationProvider.notifier).state =
        const Duration(seconds: 10);
    ref.read(wordChunkDurationsProvider.notifier).state = const [
      Duration(seconds: 10),
    ];
    ref.read(wordCuesProvider.notifier).state = buildWordCues(
      boundaries.length,
      const Duration(seconds: 10),
    );
    ref.read(currentWordIndexProvider.notifier).state = 0;
    ref.read(ttsStatusProvider.notifier).state = 'Playing';
  }

  @override
  Future<void> seekToWord(int wordIndex) async {
    seekRequests.add(wordIndex);
    final ref = _ref;
    if (ref == null) return;
    final boundaries = ref.read(wordBoundariesProvider);
    if (boundaries.isEmpty) return;
    ref.read(currentWordIndexProvider.notifier).state =
        wordIndex.clamp(0, boundaries.length - 1).toInt();
  }
}

class _FakeAudioPlayerController implements AudioPlayerController {
  final _playbackEvents = StreamController<PlaybackEvent>.broadcast();
  final _positions = StreamController<Duration>.broadcast();
  final _currentIndexes = StreamController<int?>.broadcast();
  final _playing = StreamController<bool>.broadcast();

  @override
  Stream<PlaybackEvent> get playbackEventStream => _playbackEvents.stream;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<int?> get currentIndexStream => _currentIndexes.stream;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Duration get position => Duration.zero;

  @override
  Duration get bufferedPosition => Duration.zero;

  @override
  int? get currentIndex => 0;

  @override
  bool get playing => true;

  @override
  double get speed => 1.0;

  @override
  ProcessingState get processingState => ProcessingState.ready;

  @override
  Future<void> play() async {
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    _playing.add(false);
  }

  @override
  Future<void> stop() async {
    _playing.add(false);
  }

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setAudioSource(AudioSource source) async {}

  @override
  Future<void> seek(Duration position, {int? index}) async {
    _positions.add(position);
    _currentIndexes.add(index ?? 0);
  }
}

extension on _ControllableSpeechService {
  SpeechService bind(Ref ref) {
    _ref = ref;
    return this;
  }
}
