import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Streaming Playback')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Live Highlight'),
            const SizedBox(height: 12),
            Expanded(
              child: _HighlightedText(
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
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyLarge,
          children: spans,
        ),
      ),
    );
  }
}
