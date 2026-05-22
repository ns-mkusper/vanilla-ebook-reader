import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_read_it/main.dart' as app;
import 'package:path_provider/path_provider.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full emulator import persistence voice playback flow',
      (tester) async {
    final tempDir = await getTemporaryDirectory();
    final txtFile = File('${tempDir.path}/copyright_free_notes.txt');
    final epubFile = File('${tempDir.path}/copyright_free_book.epub');
    await txtFile.writeAsString(_txtSample, flush: true);
    await epubFile.writeAsBytes(_sampleEpubBytes(), flush: true);

    await app.main();
    await tester.pump(const Duration(seconds: 2));
    await _dismissSystemSettling(tester);

    await _importPath(tester, txtFile.path, contains('TXT import fixture'));

    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
    }
    await binding.takeScreenshot('01_txt_import_editor');

    await _importPath(
        tester, epubFile.path, contains('Simple book speech fixture'));

    // Simulate an app restart in the same on-device process and verify the
    // document restored from device storage, not widget memory.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const ProviderScope(child: app.TtsApp()));
    await _pumpUntil(
      tester,
      () => _editorText(tester).contains('Simple book speech fixture'),
      timeout: const Duration(seconds: 30),
    );
    final restoredField = tester.widget<TextField>(
      find.byKey(const Key('editor.text')),
    );
    expect(
        restoredField.controller!.text, contains('Simple book speech fixture'));

    // Voice selection via actual UI. This exercises the Flite option when a
    // Flite Android TTS engine is installed and otherwise verifies the app's
    // fallback to the platform TTS engine without breaking playback.
    await tester.tap(find.text('Voice Model'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Classic Flite').last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Classic Flite'), findsOneWidget);

    await tester.tap(find.text('Read Aloud'));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 5)),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Streaming Playback'), findsOneWidget);
    expect(find.byKey(const Key('player.highlight.rich_text')), findsOneWidget);

    final wavFile = File('${tempDir.path}/just_read_it_playback_sample.wav');
    await _pumpUntil(
      tester,
      wavFile.existsSync,
      timeout: const Duration(seconds: 60),
    );
    _validateWav(await wavFile.readAsBytes());

    await binding.takeScreenshot('02_player_playback');
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
  _expectEditorText(tester, expectedText);
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

void _expectEditorText(WidgetTester tester, Matcher matcher) {
  final field = tester.widget<TextField>(find.byKey(const Key('editor.text')));
  expect(field.controller!.text, matcher);
}

void _validateWav(Uint8List bytes) {
  expect(utf8.decode(bytes.sublist(0, 4)), 'RIFF');
  expect(utf8.decode(bytes.sublist(8, 12)), 'WAVE');
  expect(utf8.decode(bytes.sublist(36, 40)), 'data');
  final data = ByteData.sublistView(bytes);
  final channels = data.getUint16(22, Endian.little);
  final sampleRate = data.getUint32(24, Endian.little);
  final bitsPerSample = data.getUint16(34, Endian.little);
  final dataLength = data.getUint32(40, Endian.little);
  expect(channels, 1);
  expect(sampleRate, greaterThanOrEqualTo(8000));
  expect(bitsPerSample, 16);
  expect(dataLength, greaterThan(sampleRate));

  var peak = 0;
  for (var i = 44; i + 1 < bytes.length; i += 2) {
    final sample = data.getInt16(i, Endian.little).abs();
    if (sample > peak) peak = sample;
  }
  expect(peak, greaterThan(2000));
}

const _txtSample =
    'TXT import fixture. This copyright-free text verifies import via UI.';

Uint8List _sampleEpubBytes() {
  return _storeOnlyZip({
    'mimetype': 'application/epub+zip',
    'OEBPS/chapter1.xhtml': '''<html><body>
<h1>Simple book speech fixture</h1>
<p>This simple book is a clear test of imported speech.</p>
<p>Just Read It should restore the document and read every sentence aloud.</p>
</body></html>''',
  });
}

Uint8List _storeOnlyZip(Map<String, String> entries) {
  final builder = BytesBuilder();
  for (final entry in entries.entries) {
    final name = utf8.encode(entry.key);
    final data = utf8.encode(entry.value);
    _writeUint32(builder, 0x04034b50);
    _writeUint16(builder, 20);
    _writeUint16(builder, 0);
    _writeUint16(builder, 0);
    _writeUint16(builder, 0);
    _writeUint16(builder, 0);
    _writeUint32(builder, 0);
    _writeUint32(builder, data.length);
    _writeUint32(builder, data.length);
    _writeUint16(builder, name.length);
    _writeUint16(builder, 0);
    builder.add(name);
    builder.add(data);
  }
  return Uint8List.fromList(builder.takeBytes());
}

void _writeUint16(BytesBuilder builder, int value) {
  builder.add([value & 0xff, (value >> 8) & 0xff]);
}

void _writeUint32(BytesBuilder builder, int value) {
  builder.add([
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ]);
}
