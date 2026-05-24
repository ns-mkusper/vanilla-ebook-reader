import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_read_it/main.dart' as app;
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full FLCL markdown import starts real playback', (tester) async {
    final tempDir = await getTemporaryDirectory();
    final flclFile = File('${tempDir.path}/flcl_lore.md');
    await flclFile.writeAsString(
      await rootBundle.loadString('test/fixtures/flcl_lore.md'),
      flush: true,
    );

    await app.main();
    await tester.pump(const Duration(seconds: 2));
    await _dismissSystemSettling(tester);

    await _importPath(tester, flclFile.path, contains('Tier 7: The Abyss'));
    expect(_editorText(tester), contains('What does Fooly Cooly mean'));
    expect(_editorText(tester), contains('See you Space Cowboy'));

    expect(find.byKey(const Key('voice.current')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('voice.current'))).data,
      'Android Male Voice',
    );

    await tester.tap(find.byKey(const Key('player.launch')),
        warnIfMissed: false);
    await _pumpUntilFound(tester, find.text('Streaming Playback'),
        timeout: const Duration(seconds: 15));
    await _pumpUntilFound(tester, find.byKey(const Key('player.status')),
        timeout: const Duration(seconds: 10));
    await _pumpUntil(
      tester,
      () {
        final status =
            tester.widget<Text>(find.byKey(const Key('player.status'))).data ??
                '';
        return status.contains('Preparing audio chunk') ||
            status.contains('Starting media player') ||
            status.contains('Playing');
      },
      timeout: const Duration(seconds: 30),
    );
    expect(find.byKey(const Key('player.highlight.rich_text')), findsOneWidget);
    expect(find.textContaining('Fooly Cooly'), findsWidgets);

    final wavFile = File('${tempDir.path}/just_read_it_playback_sample.wav');
    await _pumpUntil(
      tester,
      () => wavFile.existsSync() && wavFile.lengthSync() > 1000000,
      timeout: const Duration(minutes: 5),
    );
    final bytes = await wavFile.readAsBytes();
    _validateWav(bytes);
    debugPrint('JRI_FLCL_FULL_TEXT_PLAYBACK_VALIDATED bytes=${bytes.length}');

    await tester.tap(find.byKey(const Key('player.stop')));
    await tester.pump(const Duration(milliseconds: 500));
  });
}

Future<void> _dismissSystemSettling(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
  await tester.pump(const Duration(milliseconds: 500));
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
