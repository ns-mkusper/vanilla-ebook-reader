import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/audio_handler.dart';
import '../services/model_repository.dart';
import '../services/text_analysis.dart';
import '../services/tts_service.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.text});

  final String text;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        await ref.read(ttsServiceProvider).speak(widget.text);
      } catch (err) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playback failed: $err')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final wordIndex = ref.watch(currentWordIndexProvider);
    final boundaries = ref.watch(wordBoundariesProvider);
    final effectiveBoundaries =
        boundaries.isEmpty ? computeWordBoundaries(widget.text) : boundaries;
    final config = ref.watch(ttsConfigProvider);
    final status = ref.watch(ttsStatusProvider);
    final backendLabel = switch (config.voice.backend) {
      TtsEngineBackend.piper => 'Neural voice: ${config.voice.displayName}',
      TtsEngineBackend.fliteClassic =>
        'Classic voice: ${config.voice.displayName}',
      TtsEngineBackend.androidSystem =>
        'System voice: ${config.voice.displayName}',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Streaming Playback')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: Icon(
                  config.voice.backend == TtsEngineBackend.piper
                      ? Icons.graphic_eq
                      : Icons.record_voice_over,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
                backgroundColor: Theme.of(context).colorScheme.secondary,
                label: Text(backendLabel),
              ),
            ),
            Text(
              status,
              key: const Key('player.status'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  key: const Key('player.pause'),
                  onPressed: () async =>
                      (await ref.read(audioHandlerProvider)).pause(),
                  icon: const Icon(Icons.pause),
                  label: const Text('Pause'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const Key('player.stop'),
                  onPressed: () async {
                    await (await ref.read(audioHandlerProvider)).stop();
                    ref.read(currentWordIndexProvider.notifier).state = 0;
                  },
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Live Highlight', key: Key('player.highlight.label')),
            const SizedBox(height: 12),
            Expanded(
              child: _HighlightedText(
                key: const Key('player.highlight.text'),
                text: widget.text,
                activeIndex: wordIndex,
                boundaries: effectiveBoundaries,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    super.key,
    required this.text,
    required this.activeIndex,
    required this.boundaries,
  });

  final String text;
  final int activeIndex;
  final List<TextWordBoundary> boundaries;

  @override
  Widget build(BuildContext context) {
    if (boundaries.isEmpty) {
      return SingleChildScrollView(
        child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
      );
    }
    final spans = <TextSpan>[];
    var cursor = 0;
    final theme = Theme.of(context);
    for (final boundary in boundaries) {
      if (boundary.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, boundary.start)));
      }
      final wordText = text.substring(boundary.start, boundary.end);
      final isActive = boundary.index == activeIndex;
      spans.add(
        TextSpan(
          text: wordText,
          style: isActive
              ? TextStyle(
                  backgroundColor: theme.colorScheme.primary,
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                )
              : null,
        ),
      );
      cursor = boundary.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return SingleChildScrollView(
      child: RichText(
        key: const Key('player.highlight.rich_text'),
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyLarge,
          children: spans,
        ),
      ),
    );
  }
}
