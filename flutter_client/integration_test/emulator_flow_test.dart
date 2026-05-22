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

    await _importPath(tester, txtFile.path);
    expect(find.text('copyright_free_notes'), findsOneWidget);
    expect(find.textContaining('TXT import fixture'), findsOneWidget);

    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 500));
    }
    await binding.takeScreenshot('01_txt_import_editor');

    await _importPath(tester, epubFile.path);
    expect(find.text('copyright_free_book'), findsOneWidget);
    expect(find.textContaining('EPUB import fixture'), findsOneWidget);

    // Simulate an app restart in the same on-device process and verify the
    // document restored from device storage, not widget memory.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const ProviderScope(child: app.TtsApp()));
    await tester.pump(const Duration(seconds: 1));
    final restoredField = tester.widget<TextField>(
      find.byKey(const Key('editor.text')),
    );
    expect(restoredField.controller!.text, contains('EPUB import fixture'));

    // Voice selection via actual UI.
    await tester.tap(find.text('Voice Model'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Qwen-TTS Ethan').last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Qwen-TTS Ethan'), findsOneWidget);

    await tester.tap(find.text('Read Aloud'));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 5)),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Streaming Playback'), findsOneWidget);
    expect(find.byKey(const Key('player.highlight.rich_text')), findsOneWidget);
    await binding.takeScreenshot('02_player_playback');

    final wavFile = File('${tempDir.path}/just_read_it_voice_sample.wav');
    expect(await wavFile.exists(), isTrue);
    _validateWav(await wavFile.readAsBytes());
  });
}

Future<void> _dismissSystemSettling(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _importPath(WidgetTester tester, String path) async {
  await tester.tap(find.byKey(const Key('document.import')));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.enterText(find.byKey(const Key('import.path')), path);
  await tester.tap(find.byKey(const Key('import.confirm')));
  await tester.pump(const Duration(seconds: 1));
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
  expect(sampleRate, 16000);
  expect(bitsPerSample, 16);
  expect(dataLength, greaterThan(16000));

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
<h1>EPUB import fixture</h1>
<p>This copyright-free EPUB validates import through the emulator UI.</p>
<p>Just Read It should restore and read this document aloud.</p>
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
