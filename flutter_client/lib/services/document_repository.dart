import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final documentDirectoryProvider = FutureProvider<Directory>((ref) async {
  final base = await getApplicationDocumentsDirectory();
  final directory = Directory(p.join(base.path, 'just_read_it'));
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return directory;
});

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  final directory = ref.watch(documentDirectoryProvider).valueOrNull;
  return DocumentRepository(directory: directory);
});

@immutable
class ReaderDocument {
  const ReaderDocument({
    required this.title,
    required this.text,
    this.sourcePath,
  });

  final String title;
  final String text;
  final String? sourcePath;

  ReaderDocument copyWith({String? title, String? text, String? sourcePath}) {
    return ReaderDocument(
      title: title ?? this.title,
      text: text ?? this.text,
      sourcePath: sourcePath ?? this.sourcePath,
    );
  }
}

class DocumentRepository {
  DocumentRepository({Directory? directory}) : _directory = directory;

  final Directory? _directory;

  static const draftFileName = 'current_draft.txt';
  static const draftTitleFileName = 'current_draft.title';

  Future<ReaderDocument> loadDraft() async {
    final dir = await _ensureDirectory();
    final textFile = File(p.join(dir.path, draftFileName));
    final titleFile = File(p.join(dir.path, draftTitleFileName));
    final text = await textFile.exists() ? await textFile.readAsString() : '';
    final title = await titleFile.exists()
        ? (await titleFile.readAsString()).trim()
        : 'Untitled note';
    return ReaderDocument(
      title: title.isEmpty ? 'Untitled note' : title,
      text: text,
    );
  }

  Future<void> saveDraft(ReaderDocument document) async {
    final dir = await _ensureDirectory();
    await Future.wait([
      File(p.join(dir.path, draftFileName)).writeAsString(document.text),
      File(p.join(dir.path, draftTitleFileName)).writeAsString(document.title),
    ]);
  }

  Future<ReaderDocument> importPath(String path) async {
    final extension = p.extension(path).toLowerCase();
    if (extension == '.txt' || extension == '.md' || extension == '.text') {
      return importTextFile(File(path));
    }
    if (extension == '.epub') {
      return importEpubFile(File(path));
    }
    throw UnsupportedError(
        'Unsupported file type "$extension". Use .txt or .epub.');
  }

  Future<ReaderDocument> importTextFile(File file) async {
    final text = await file.readAsString();
    final document = ReaderDocument(
      title: _titleFromPath(file.path),
      text: text,
      sourcePath: file.path,
    );
    await saveDraft(document);
    return document;
  }

  Future<ReaderDocument> importEpubFile(File file) async {
    final bytes = await file.readAsBytes();
    final text = EpubTextExtractor.extract(bytes);
    if (text.trim().isEmpty) {
      throw const FormatException('No readable text found in EPUB.');
    }
    final document = ReaderDocument(
      title: _titleFromPath(file.path),
      text: text,
      sourcePath: file.path,
    );
    await saveDraft(document);
    return document;
  }

  Future<Directory> _ensureDirectory() async {
    final directory = _directory ??
        Directory(p.join(
          (await getApplicationDocumentsDirectory()).path,
          'just_read_it',
        ));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static String _titleFromPath(String path) {
    final basename = p.basenameWithoutExtension(path).trim();
    return basename.isEmpty ? 'Untitled note' : basename;
  }
}

class EpubTextExtractor {
  const EpubTextExtractor._();

  static String extract(Uint8List bytes) {
    final entries = _ZipReader(bytes).readEntries();
    final readableEntries = entries.entries
        .where((entry) => _isReadableContent(entry.key))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final chunks = <String>[];
    for (final entry in readableEntries) {
      final decoded = utf8.decode(entry.value, allowMalformed: true);
      final cleaned = _htmlToText(decoded);
      if (cleaned.isNotEmpty) {
        chunks.add(cleaned);
      }
    }
    return chunks.join('\n\n').trim();
  }

  static bool _isReadableContent(String path) {
    final lower = path.toLowerCase();
    if (!(lower.endsWith('.xhtml') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm'))) {
      return false;
    }
    return !lower.contains('nav.') && !lower.contains('toc.');
  }

  static String _htmlToText(String input) {
    var text = input
        .replaceAll(
            RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'</(p|div|h[1-6]|li|br|section|chapter)>',
                caseSensitive: false),
            '\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    const entities = {
      '&nbsp;': ' ',
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&apos;': "'",
    };
    for (final entry in entities.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final codePoint = int.tryParse(match.group(1)!);
      return codePoint == null
          ? match.group(0)!
          : String.fromCharCode(codePoint);
    });
    return text
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .join('\n')
        .trim();
  }
}

class _ZipEntry {
  const _ZipEntry(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

class _ZipReader {
  _ZipReader(this.bytes);

  final Uint8List bytes;

  Map<String, Uint8List> readEntries() {
    final entries = <String, Uint8List>{};
    var offset = 0;
    while (offset + 30 <= bytes.length) {
      final signature = _uint32(offset);
      if (signature != 0x04034b50) {
        offset++;
        continue;
      }
      final flags = _uint16(offset + 6);
      final method = _uint16(offset + 8);
      final compressedSize = _uint32(offset + 18);
      final fileNameLength = _uint16(offset + 26);
      final extraFieldLength = _uint16(offset + 28);
      final nameStart = offset + 30;
      final nameEnd = nameStart + fileNameLength;
      final dataStart = nameEnd + extraFieldLength;
      if (nameEnd > bytes.length || dataStart > bytes.length) {
        break;
      }
      if ((flags & 0x08) != 0) {
        throw const FormatException(
          'EPUB ZIP entries with data descriptors are not supported.',
        );
      }
      final dataEnd = dataStart + compressedSize;
      if (dataEnd > bytes.length) {
        break;
      }
      final name = utf8.decode(bytes.sublist(nameStart, nameEnd));
      if (!name.endsWith('/')) {
        entries[name] = _decodeEntry(
          _ZipEntry(name, bytes.sublist(dataStart, dataEnd)),
          method,
        );
      }
      offset = dataEnd;
    }
    return entries;
  }

  Uint8List _decodeEntry(_ZipEntry entry, int method) {
    return switch (method) {
      0 => entry.bytes,
      8 => Uint8List.fromList(ZLibDecoder(raw: true).convert(entry.bytes)),
      _ => throw FormatException(
          'Unsupported compression method $method in ${entry.name}.',
        ),
    };
  }

  int _uint16(int offset) => bytes[offset] | (bytes[offset + 1] << 8);

  int _uint32(int offset) => _uint16(offset) | (_uint16(offset + 2) << 16);
}
