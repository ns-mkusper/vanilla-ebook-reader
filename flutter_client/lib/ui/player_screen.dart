import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      await ref.read(ttsServiceProvider).speak(widget.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final wordIndex = ref.watch(currentWordIndexProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Streaming Playback')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Live Highlight'),
            const SizedBox(height: 12),
            Expanded(child: _HighlightedText(text: widget.text, activeIndex: wordIndex)),
          ],
        ),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({required this.text, required this.activeIndex});

  final String text;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final before = text.substring(0, activeIndex.clamp(0, text.length));
    final active = activeIndex < text.length ? text[activeIndex] : '';
    final after = activeIndex + 1 < text.length ? text.substring(activeIndex + 1) : '';

    if (before.isNotEmpty) {
      spans.add(TextSpan(text: before));
    }
    if (active.isNotEmpty) {
      spans.add(TextSpan(
        text: active,
        style: TextStyle(
          backgroundColor: Theme.of(context).colorScheme.primary,
          color: Theme.of(context).colorScheme.onPrimary,
          fontWeight: FontWeight.bold,
        ),
      ));
    }
    if (after.isNotEmpty) {
      spans.add(TextSpan(text: after));
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
