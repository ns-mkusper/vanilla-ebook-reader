import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_read_it/main.dart' as app;
import 'package:path_provider/path_provider.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('txt import via emulator UI produces editor screenshot',
      (tester) async {
    final tempDir = await getTemporaryDirectory();
    final txtFile = File('${tempDir.path}/copyright_free_notes.txt');
    await txtFile.writeAsString(_txtSample, flush: true);

    await app.main();
    await tester.pump(const Duration(seconds: 2));
    await _dismissSystemSettling(tester);

    await _importPath(tester, txtFile.path, contains('TXT import fixture'));

    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
    }
    await binding.takeScreenshot('01_txt_import_editor');
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

const _txtSample =
    'TXT import fixture. This copyright-free text verifies import via UI.';
