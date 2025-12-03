import 'dart:math';

/// Represents the character range for a single word token.
class TextWordBoundary {
  const TextWordBoundary(
      {required this.index, required this.start, required this.end});

  final int index;
  final int start;
  final int end;
}

/// Represents the playback window for a single word.
class WordCue {
  const WordCue(
      {required this.wordIndex, required this.start, required this.end});

  final int wordIndex;
  final Duration start;
  final Duration end;

  bool contains(Duration position) {
    return position >= start && position < end;
  }
}

List<TextWordBoundary> computeWordBoundaries(String text) {
  final matches = RegExp(r'\S+').allMatches(text);
  if (matches.isEmpty) {
    return const [];
  }
  final boundaries = <TextWordBoundary>[];
  var index = 0;
  for (final match in matches) {
    boundaries.add(
      TextWordBoundary(
        index: index++,
        start: match.start,
        end: match.end,
      ),
    );
  }
  return boundaries;
}

List<WordCue> buildWordCues(int wordCount, Duration totalDuration) {
  if (wordCount <= 0 || totalDuration.inMicroseconds == 0) {
    return [];
  }
  final cues = <WordCue>[];
  final stepMicros = max(totalDuration.inMicroseconds ~/ wordCount, 1);
  for (var i = 0; i < wordCount; i++) {
    final start = Duration(microseconds: i * stepMicros);
    final end = Duration(
        microseconds: min((i + 1) * stepMicros, totalDuration.inMicroseconds));
    cues.add(WordCue(wordIndex: i, start: start, end: end));
  }
  if (cues.isNotEmpty) {
    final last = cues.last;
    cues[cues.length - 1] = WordCue(
      wordIndex: last.wordIndex,
      start: last.start,
      end: totalDuration,
    );
  }
  return cues;
}

int wordIndexForPosition(Duration position, List<WordCue> cues) {
  if (cues.isEmpty) {
    return 0;
  }
  for (final cue in cues) {
    if (cue.contains(position)) {
      return cue.wordIndex;
    }
  }
  return cues.last.wordIndex;
}
