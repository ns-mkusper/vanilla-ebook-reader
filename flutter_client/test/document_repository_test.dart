import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_read_it/services/document_repository.dart';

void main() {
  late Directory tempDir;
  late DocumentRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('just_read_it_docs_');
    repository = DocumentRepository(directory: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
      'imports copyright-free text files and persists the active draft quickly',
      () async {
    final source = File('${tempDir.path}/gemini-output.txt');
    const sample =
        'Copyright-free sample text. Gemini produced concise reading notes.';
    await source.writeAsString(sample);

    final stopwatch = Stopwatch()..start();
    final document = await repository.importPath(source.path);
    stopwatch.stop();

    expect(stopwatch.elapsedMilliseconds, lessThan(75));
    expect(document.title, 'gemini-output');
    expect(document.text, sample);

    final restored = await repository.loadDraft();
    expect(restored.title, 'gemini-output');
    expect(restored.text, sample);
  });

  test('extracts readable text from a copyright-free EPUB sample', () async {
    final epub = File('${tempDir.path}/open-sample.epub');
    await epub.writeAsBytes(_sampleEpubBytes());

    final stopwatch = Stopwatch()..start();
    final document = await repository.importEpubFile(epub);
    stopwatch.stop();

    expect(stopwatch.elapsedMilliseconds, lessThan(100));
    expect(document.title, 'open-sample');
    expect(document.text, contains('Public-domain style sample chapter'));
    expect(
        document.text, contains('Just Read It should highlight every word.'));
    expect(document.text, isNot(contains('<p>')));
  });
}

Uint8List _sampleEpubBytes() {
  final entries = <String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''',
    'OEBPS/chapter1.xhtml': '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><body>
<h1>Public-domain style sample chapter</h1>
<p>This copyright-free fixture was written for automated tests.</p>
<p>Just Read It should highlight every word.</p>
</body></html>''',
  };
  return _storeOnlyZip(entries);
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
