import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'components.dart';
import '../services/document_picker.dart';
import '../services/document_repository.dart';
import '../services/text_analysis.dart';
import '../services/tts_service.dart';
import 'player_screen.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final TextEditingController _controller = TextEditingController();
  var _title = 'Untitled note';
  Timer? _draftSaveDebounce;
  var _status = 'Loading saved text...';
  var _hydrating = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChanged);
    Future.microtask(_loadDraft);
  }

  @override
  void dispose() {
    _draftSaveDebounce?.cancel();
    _controller
      ..removeListener(_handleTextChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadDraft() async {
    final repository = ref.read(documentRepositoryProvider);
    final document = await repository.loadDraft();
    if (!mounted) return;
    final userAlreadyEnteredText = _controller.text.trim().isNotEmpty;
    _hydrating = true;
    if (!userAlreadyEnteredText) {
      _controller.text = document.text;
    }
    setState(() {
      if (!userAlreadyEnteredText) {
        _title = document.title;
      }
      _status = userAlreadyEnteredText
          ? 'Saved'
          : document.text.trim().isEmpty
              ? 'Paste text, import a file, or start a new note.'
              : 'Restored saved text.';
      _hydrating = false;
    });
  }

  void _handleTextChanged() {
    if (!_hydrating) {
      _scheduleDraftSave();
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _scheduleDraftSave() {
    _draftSaveDebounce?.cancel();
    _draftSaveDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_saveCurrentDraft());
    });
  }

  Future<void> _saveCurrentDraft() async {
    final repository = ref.read(documentRepositoryProvider);
    await repository.saveDraft(ReaderDocument(
      title: _title,
      text: _controller.text,
    ));
    if (!mounted) return;
    setState(() {
      _status = 'Saved';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: _buildLaunchButton(context),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 160),
                    child: Text(
                      _title,
                      key: const Key('document.title'),
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('document.new'),
                    icon: const Icon(Icons.note_add_outlined),
                    label: const Text('New Text'),
                    onPressed: _startNewDocument,
                  ),
                  FilledButton.icon(
                    key: const Key('document.import'),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Import'),
                    onPressed: _importFromFileBrowser,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _status,
                key: const Key('document.status'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('editor.text'),
                controller: _controller,
                minLines: 8,
                maxLines: 14,
                textInputAction: TextInputAction.newline,
                autofillHints: null,
                decoration: const InputDecoration(
                  labelText: 'Text to read aloud',
                  hintText:
                      'Paste reading notes, ebook text, or imported content...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const ModelSelectorCard(),
              const SizedBox(height: 12),
              const SpeedSlider(),
              const SizedBox(height: 12),
              const PitchSlider(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLaunchButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        key: const Key('player.launch'),
        icon: const Icon(Icons.graphic_eq),
        label: const Text('Read Aloud'),
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => _launchPlayer(context),
      ),
    );
  }

  Future<void> _importFromFileBrowser() async {
    const enablePathDialog = bool.fromEnvironment(
      'JRI_ENABLE_IMPORT_PATH_DIALOG',
    );
    if (enablePathDialog) {
      await _showImportPathDialog();
      return;
    }

    setState(() {
      _status = 'Opening file browser...';
    });
    try {
      final picked =
          await ref.read(documentPickerProvider).pickReadableDocument();
      if (picked == null) {
        if (!mounted) return;
        setState(() => _status = 'Import cancelled.');
        return;
      }
      final repository = ref.read(documentRepositoryProvider);
      final document = await repository.importBytes(
        name: picked.name,
        bytes: picked.bytes,
        sourcePath: picked.path,
      );
      _applyImportedDocument(document);
    } catch (err) {
      _showImportFailure(err);
    }
  }

  Future<void> _showImportPathDialog() async {
    final path = await showDialog<String>(
      context: context,
      builder: (context) => const _ImportPathDialog(),
    );
    if (path == null || path.trim().isEmpty) return;
    await _importPath(path.trim());
  }

  Future<void> _importPath(String path) async {
    setState(() {
      _status = 'Importing file...';
    });
    try {
      final repository = ref.read(documentRepositoryProvider);
      final document = await repository.importPath(path);
      _applyImportedDocument(document);
    } catch (err) {
      _showImportFailure(err);
    }
  }

  void _applyImportedDocument(ReaderDocument document) {
    if (!mounted) return;
    _hydrating = true;
    _controller.text = document.text;
    setState(() {
      _title = document.title;
      _status = 'Imported ${document.title}';
      _hydrating = false;
    });
  }

  void _showImportFailure(Object err) {
    if (!mounted) return;
    setState(() {
      _status = 'Import failed: $err';
    });
  }

  Future<void> _startNewDocument() async {
    _hydrating = true;
    _controller.clear();
    setState(() {
      _title = 'Untitled note';
      _status = 'New text file ready.';
      _hydrating = false;
    });
    await _saveCurrentDraft();
  }

  Future<void> _launchPlayer(BuildContext context) async {
    final text = _controller.text;
    unawaited(_saveCurrentDraft());
    ref.read(wordBoundariesProvider.notifier).state =
        computeWordBoundaries(text);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(text: text)),
    );
  }
}

class _ImportPathDialog extends StatefulWidget {
  const _ImportPathDialog();

  @override
  State<_ImportPathDialog> createState() => _ImportPathDialogState();
}

class _ImportPathDialogState extends State<_ImportPathDialog> {
  final TextEditingController _pathController = TextEditingController();
  var _submitted = false;

  void _submit([String? value]) {
    if (_submitted) return;
    _submitted = true;
    FocusScope.of(context).unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    Navigator.of(context).pop((value ?? _pathController.text).trim());
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import TXT or EPUB'),
      content: TextField(
        key: const Key('import.path'),
        controller: _pathController,
        autofocus: true,
        textInputAction: TextInputAction.done,
        autofillHints: null,
        onEditingComplete: _submit,
        onSubmitted: _submit,
        decoration: const InputDecoration(
          labelText: 'File path',
          hintText: '/path/to/book.epub',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('import.confirm'),
          onPressed: _submit,
          child: const Text('Import'),
        ),
      ],
    );
  }
}
