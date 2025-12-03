import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../genui/components.dart';
import '../genui/panel.dart';
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

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TTS Beast Editor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.smart_toy),
            onPressed: () => _showGenUiSheet(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _controller,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'Paste or dictate text to synthesize...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const ModelSelectorCard(),
              const SizedBox(height: 12),
              const LlmModelDropdown(),
              const SizedBox(height: 12),
              const SpeedSlider(),
              const SizedBox(height: 8),
              const ThemeToggle(),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.graphic_eq),
                  label: const Text('Stream to Player'),
                  onPressed: _controller.text.trim().isEmpty
                      ? null
                      : () => _launchPlayer(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showGenUiSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const FractionallySizedBox(
        heightFactor: 0.9,
        child: GenUiPanel(),
      ),
    );
  }

  Future<void> _launchPlayer(BuildContext context) async {
    final text = _controller.text;
    ref.read(wordBoundariesProvider.notifier).state =
        computeWordBoundaries(text);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(text: text)),
    );
  }
}
