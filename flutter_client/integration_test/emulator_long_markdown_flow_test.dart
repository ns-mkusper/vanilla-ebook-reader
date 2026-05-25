import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_read_it/main.dart' as app;
import 'package:path_provider/path_provider.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('long markdown import starts real playback quickly',
      (tester) async {
    final tempDir = await getTemporaryDirectory();
    final longMarkdownFile = File('${tempDir.path}/long_markdown_fixture.md');
    await longMarkdownFile.writeAsString(
      await rootBundle.loadString('test/fixtures/long_markdown_fixture.md'),
      flush: true,
    );

    await app.main();
    await tester.pump(const Duration(seconds: 2));
    await _dismissSystemSettling(tester);

    await _importPath(tester, longMarkdownFile.path,
        contains('Tier 7: Synthetic Reading Stress Layer'));
    final importedText = _editorText(tester);
    expect(importedText, contains('long-form markdown fixture verifies'));
    expect(importedText, contains('See you at the end'));

    expect(find.byKey(const Key('voice.current')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('voice.current'))).data,
      'Android Default Voice',
    );
    await tester.drag(
        find.byKey(const Key('playback.speed')), const Offset(500, 0));
    await tester.pump(const Duration(milliseconds: 300));

    final launchTimer = Stopwatch()..start();
    await _tapLaunchButton(tester);
    await _pumpUntilFound(tester, find.text('Streaming Playback'),
        timeout: const Duration(seconds: 60));
    await _pumpUntilFound(tester, find.byKey(const Key('player.status')),
        timeout: const Duration(seconds: 10));
    await _pumpUntil(
      tester,
      () {
        final status =
            tester.widget<Text>(find.byKey(const Key('player.status'))).data ??
                '';
        return status.contains('Preparing instant playback') ||
            status.contains('Preparing audio chunk') ||
            status.contains('Starting media player') ||
            status.contains('Playing');
      },
      timeout: const Duration(seconds: 30),
    );
    await _pumpUntil(
      tester,
      () {
        final status =
            tester.widget<Text>(find.byKey(const Key('player.status'))).data ??
                '';
        return status.contains('Playing');
      },
      timeout: const Duration(seconds: 30),
    );
    final playbackStartMs = launchTimer.elapsedMilliseconds;
    debugPrint('JRI_LONG_DOC_PLAYBACK_STARTED_AFTER_MS=$playbackStartMs');
    expect(playbackStartMs, lessThanOrEqualTo(30000));
    final highlightFinder = find.byKey(const Key('player.highlight.rich_text'));
    expect(highlightFinder, findsOneWidget);
    final highlightedText =
        tester.widget<RichText>(highlightFinder).text.toPlainText();
    expect(highlightedText, contains('long-form markdown fixture'));
    expect(highlightedText, contains('See you at the end'));

    final wavFile = File('${tempDir.path}/just_read_it_playback_sample.wav');
    await _pumpUntil(
      tester,
      () => wavFile.existsSync() && wavFile.lengthSync() > 100000,
      timeout: const Duration(minutes: 2),
    );
    debugPrint(
      'JRI_LONG_DOC_PLAYBACK_PROOF_MS=${launchTimer.elapsedMilliseconds}',
    );
    await tester.tap(find.byKey(const Key('player.pause')));
    await _pumpUntilFound(tester, find.text('Resume'),
        timeout: const Duration(seconds: 10));
    final pausedProgress = _playerProgress(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(
      _playerProgress(tester).current,
      lessThanOrEqualTo(pausedProgress.current + 2),
    );

    await tester.tap(find.byKey(const Key('player.pause')));
    await _pumpUntilFound(tester, find.text('Pause'),
        timeout: const Duration(seconds: 10));
    await _pumpUntil(
      tester,
      () {
        final progress = _playerProgress(tester);
        return progress.total > 0 && progress.current >= progress.total ~/ 2;
      },
      timeout: const Duration(minutes: 25),
    );
    final halfProgress = _playerProgress(tester);
    debugPrint(
      'JRI_LONG_DOC_HALF_PLAYBACK_VALIDATED word=${halfProgress.current} total=${halfProgress.total}',
    );

    final bytes = await wavFile.readAsBytes();
    _validateWav(bytes);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['playbackWavBase64'] = base64Encode(bytes);
    binding.reportData!['playbackWavName'] =
        'long_markdown_playback_sample_from_emulator.wav';
    binding.reportData!['validatedPlaybackSource'] = true;
    binding.reportData!['longMarkdownFullTextLength'] = importedText.length;
    debugPrint(
        'JRI_LONG_DOC_FULL_TEXT_PLAYBACK_VALIDATED bytes=${bytes.length}');

    await tester.tap(find.byKey(const Key('player.stop')));
    await tester.pump(const Duration(milliseconds: 500));
  });
}

Future<void> _dismissSystemSettling(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _tapLaunchButton(WidgetTester tester) async {
  final launchButton = find.byKey(const Key('player.launch'));
  await _pumpUntilFound(tester, launchButton,
      timeout: const Duration(seconds: 15));
  await tester.pump(const Duration(milliseconds: 500));
  final button = tester.widget<ElevatedButton>(launchButton);
  expect(button.enabled, isTrue,
      reason:
          'Read Aloud must be enabled after importing the full long markdown text.');

  await tester.ensureVisible(launchButton);
  await tester.pump(const Duration(milliseconds: 300));

  final hitTestableButton = launchButton.hitTestable();
  expect(hitTestableButton, findsOneWidget,
      reason: 'Read Aloud must be exposed as a tappable Flutter control.');
  final center = tester.getCenter(hitTestableButton);
  debugPrint('JRI_LONG_DOC_TAP_READ_ALOUD center=$center');
  await tester.tap(hitTestableButton);
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _importPath(
  WidgetTester tester,
  String path,
  Matcher expectedText,
) async {
  await _openImportDialog(tester);
  await tester.enterText(find.byKey(const Key('import.path')), path);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump(const Duration(milliseconds: 300));
  if (find.byKey(const Key('import.path')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('import.confirm')),
        warnIfMissed: false);
  }
  await _pumpUntil(
    tester,
    () => _editorText(tester).contains(_expectedNeedle(expectedText)),
    timeout: const Duration(seconds: 30),
  );
}

Future<void> _openImportDialog(WidgetTester tester) async {
  final importPath = find.byKey(const Key('import.path'));
  final importButton = find.byKey(const Key('document.import'));
  for (var attempt = 0; attempt < 4; attempt++) {
    await tester.ensureVisible(importButton);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(importButton, warnIfMissed: false);
    await tester.pump(const Duration(seconds: 1));
    if (importPath.evaluate().isNotEmpty) return;
  }
  await _pumpUntilFound(tester, importPath,
      timeout: const Duration(seconds: 15));
}

String _editorText(WidgetTester tester) {
  final field = tester.widget<TextField>(find.byKey(const Key('editor.text')));
  return field.controller!.text;
}

_PlayerProgress _playerProgress(WidgetTester tester) {
  final text =
      tester.widget<Text>(find.byKey(const Key('player.progress'))).data ?? '';
  final match = RegExp(r'Word (\d+) of (\d+)').firstMatch(text);
  if (match == null) return const _PlayerProgress(0, 0);
  return _PlayerProgress(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
  );
}

class _PlayerProgress {
  const _PlayerProgress(this.current, this.total);

  final int current;
  final int total;
}

String _expectedNeedle(Matcher matcher) {
  final description = StringDescription();
  matcher.describe(description);
  final text = description.toString();
  final match = RegExp(r"contains '([^']+)'").firstMatch(text);
  return match?.group(1) ?? '';
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  await _pumpUntil(tester, () => finder.evaluate().isNotEmpty,
      timeout: timeout);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (condition()) return;
  }
  fail('Timed out waiting for emulator UI condition');
}

void _validateWav(Uint8List bytes) {
  expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
  expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
  final data = ByteData.sublistView(bytes);
  final channels = data.getUint16(22, Endian.little);
  final sampleRate = data.getUint32(24, Endian.little);
  final bitsPerSample = data.getUint16(34, Endian.little);
  final dataLength = data.getUint32(40, Endian.little);
  expect(channels, 1);
  expect(sampleRate, greaterThanOrEqualTo(8000));
  expect(bitsPerSample, 16);
  expect(dataLength, greaterThan(sampleRate));
}
