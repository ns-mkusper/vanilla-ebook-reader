import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/audio_handler.dart';
import '../services/text_analysis.dart';
import '../services/tts_service.dart';
import 'components.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.text});

  final String text;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  var _paused = false;

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

  Future<void> _togglePause() async {
    final shouldResume = _paused;
    setState(() => _paused = !shouldResume);
    ref.read(ttsStatusProvider.notifier).state =
        shouldResume ? 'Playing' : 'Paused';
    final audioHandler = await ref.read(audioHandlerProvider);
    if (shouldResume) {
      await audioHandler.play();
    } else {
      await audioHandler.pause();
    }
  }

  Future<void> _stopPlayback() async {
    ref.read(ttsStopSignalProvider.notifier).state++;
    final audioHandler = await ref.read(audioHandlerProvider);
    await audioHandler.stop();
    if (!mounted) return;
    setState(() => _paused = false);
    ref.read(currentWordIndexProvider.notifier).state = 0;
    ref.read(ttsStatusProvider.notifier).state = 'Stopped';
  }

  @override
  Widget build(BuildContext context) {
    final wordIndex = ref.watch(currentWordIndexProvider);
    final boundaries = ref.watch(wordBoundariesProvider);
    final effectiveBoundaries =
        boundaries.isEmpty ? computeWordBoundaries(widget.text) : boundaries;
    final status = ref.watch(ttsStatusProvider);
    final totalWords = effectiveBoundaries.length;
    final currentWord = totalWords == 0 ? 0 : wordIndex + 1;
    final progressValue = totalWords == 0
        ? 0.0
        : (currentWord / totalWords).clamp(0.0, 1.0).toDouble();
    return Scaffold(
      appBar: AppBar(title: const Text('Streaming Playback')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Word $currentWord of $totalWords',
              key: const Key('player.progress'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              key: const Key('player.seekbar'),
              value: progressValue,
              minHeight: 6,
              borderRadius: BorderRadius.circular(999),
            ),
            const SizedBox(height: 12),
            const PlaybackPreferenceControls(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('player.pause'),
                    onPressed: _togglePause,
                    icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                    label: Text(_paused ? 'Resume' : 'Pause'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('player.stop'),
                    onPressed: _stopPlayback,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              status,
              key: const Key('player.status'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
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
