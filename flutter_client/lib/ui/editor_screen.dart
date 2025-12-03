import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../genui/agent.dart';
import '../genui/components.dart';
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
  Widget build(BuildContext context) {
    final config = ref.watch(ttsConfigProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('TTS Beast Editor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.smart_toy),
            onPressed: () async {
              await _showGenUiDialog();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'Type or paste text to synthesize...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Model: ${config.modelPath ?? 'Unset'}'),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Stream to Player'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PlayerScreen(text: _controller.text)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showGenUiDialog() async {
    final agent = ref.read(genUiAgentProvider);
    final config = ref.watch(ttsConfigProvider);
    final controller = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GenUI Prompt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: 'Describe your setup...'),
            ),
            const SizedBox(height: 16),
            const ModelSelectorCard(),
            const SpeedSlider(),
            const ThemeToggle(),
            const SizedBox(height: 8),
            Text('Current rate: ${config.rate.toStringAsFixed(2)}x'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await agent.applyPrompt(controller.text);
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('Generate'),
          ),
        ],
      ),
    );
  }
}
