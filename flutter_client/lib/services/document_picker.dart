import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final documentPickerProvider = Provider<DocumentPicker>((_) {
  return const NativeDocumentPicker();
});

class PickedDocumentFile {
  const PickedDocumentFile({
    required this.name,
    required this.bytes,
    this.path,
  });

  final String name;
  final Uint8List bytes;
  final String? path;
}

abstract class DocumentPicker {
  Future<PickedDocumentFile?> pickReadableDocument();
}

class NativeDocumentPicker implements DocumentPicker {
  const NativeDocumentPicker();

  @override
  Future<PickedDocumentFile?> pickReadableDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'text', 'md', 'markdown', 'epub'],
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file == null) {
      return null;
    }
    var bytes = file.bytes;
    final path = file.path;
    if (bytes == null && path != null) {
      bytes = await File(path).readAsBytes();
    }
    if (bytes == null) {
      return null;
    }
    return PickedDocumentFile(
      name: file.name,
      path: path,
      bytes: bytes,
    );
  }
}
