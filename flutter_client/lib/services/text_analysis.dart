import 'dart:math';

/// Represents the character range for a single word token.
class TextWordBoundary {
  const TextWordBoundary({
    required this.index,
    required this.start,
    required this.end,
  });

  final int index;
  final int start;
  final int end;
}

/// Represents the playback window for a single word.
///
/// [start] and [end] are positions on the whole media item's advertised
/// timeline. [localStart] and [localEnd] are positions inside [chunkIndex]. For
/// single-file playback these values are identical. For chunked queue playback,
/// seeking must use the chunk-local values so just_audio jumps to the selected
/// queued audio item instead of treating the offset as part of the current item.
class WordCue {
  const WordCue({
    required this.wordIndex,
    required this.start,
    required this.end,
    this.chunkIndex = 0,
    Duration? localStart,
    Duration? localEnd,
  })  : localStart = localStart ?? start,
        localEnd = localEnd ?? end;

  final int wordIndex;
  final Duration start;
  final Duration end;
  final int chunkIndex;
  final Duration localStart;
  final Duration localEnd;

  bool contains(Duration position) {
    return position >= start && position < end;
  }
}

/// A seek target that can be passed directly to the audio layer.
class WordSeekTarget {
  const WordSeekTarget({required this.position, this.chunkIndex});

  final Duration position;
  final int? chunkIndex;
}

List<TextWordBoundary> computeWordBoundaries(String text) {
  final matches = RegExp(r'\S+').allMatches(text);
  if (matches.isEmpty) {
    return const [];
  }
  final boundaries = <TextWordBoundary>[];
  var index = 0;
  for (final match in matches) {
    final speechRange = _speechTokenRange(text, match.start, match.end);
    if (speechRange == null) continue;
    boundaries.add(
      TextWordBoundary(
        index: index++,
        start: speechRange.start,
        end: speechRange.end,
      ),
    );
  }
  return boundaries;
}

({int start, int end})? _speechTokenRange(String text, int start, int end) {
  int? speechStart;
  int? speechEnd;
  var offset = start;
  for (final rune in text.substring(start, end).runes) {
    final width = rune > 0xffff ? 2 : 1;
    if (_isSpeechRune(rune)) {
      speechStart ??= offset;
      speechEnd = offset + width;
    }
    offset += width;
  }

  return speechStart != null && speechEnd != null
      ? (start: speechStart, end: speechEnd)
      : null;
}

bool _isSpeechRune(int rune) {
  return (rune >= 0x30 && rune <= 0x39) ||
      (rune >= 0x41 && rune <= 0x5a) ||
      (rune >= 0x61 && rune <= 0x7a) ||
      (rune >= 0xc0 && rune <= 0xd6) ||
      (rune >= 0xd8 && rune <= 0xf6) ||
      (rune >= 0xf8 && rune <= 0x2af);
}

List<WordCue> buildWordCues(int wordCount, Duration totalDuration) {
  if (wordCount <= 0 || totalDuration.inMicroseconds == 0) {
    return [];
  }
  return _buildCuesForWindow(
    wordOffset: 0,
    wordCount: wordCount,
    chunkIndex: 0,
    globalStart: Duration.zero,
    localStart: Duration.zero,
    duration: totalDuration,
  );
}

/// Builds a whole-document word timeline from actual per-chunk durations.
///
/// The previous highlighter treated every word as having the same duration
/// across the entire document. That drifts badly for chunked playback because
/// the media player reports a chunk-local position while each queued audio file
/// has its own measured duration. This timeline keeps the UI's global progress
/// and each queued item's seek/highlight position tied to measured audio
/// durations whenever they are available.
List<WordCue> buildChunkedWordCues({
  required List<int> chunkWordCounts,
  required List<Duration> chunkDurations,
  required Duration fallbackTotalDuration,
}) {
  if (chunkWordCounts.isEmpty) {
    return const [];
  }
  final totalWords = chunkWordCounts.fold<int>(0, (sum, count) => sum + count);
  if (totalWords <= 0) {
    return const [];
  }

  final cues = <WordCue>[];
  var wordOffset = 0;
  var globalStart = Duration.zero;
  for (var chunkIndex = 0; chunkIndex < chunkWordCounts.length; chunkIndex++) {
    final wordCount = chunkWordCounts[chunkIndex];
    if (wordCount <= 0) continue;
    final duration = chunkIndex < chunkDurations.length
        ? chunkDurations[chunkIndex]
        : estimateChunkDuration(
            chunkIndex: chunkIndex,
            chunkWordCounts: chunkWordCounts,
            fallbackTotalDuration: fallbackTotalDuration,
          );
    final safeDuration = duration > Duration.zero
        ? duration
        : estimateChunkDuration(
            chunkIndex: chunkIndex,
            chunkWordCounts: chunkWordCounts,
            fallbackTotalDuration: fallbackTotalDuration,
          );
    final chunkCues = _buildCuesForWindow(
      wordOffset: wordOffset,
      wordCount: wordCount,
      chunkIndex: chunkIndex,
      globalStart: globalStart,
      localStart: Duration.zero,
      duration: safeDuration,
    );
    cues.addAll(chunkCues);
    wordOffset += wordCount;
    globalStart += safeDuration;
  }
  return cues;
}

List<WordCue> _buildCuesForWindow({
  required int wordOffset,
  required int wordCount,
  required int chunkIndex,
  required Duration globalStart,
  required Duration localStart,
  required Duration duration,
}) {
  if (wordCount <= 0 || duration.inMicroseconds == 0) {
    return const [];
  }
  final cues = <WordCue>[];
  final stepMicros = max(duration.inMicroseconds ~/ wordCount, 1);
  for (var i = 0; i < wordCount; i++) {
    final startMicros = i * stepMicros;
    final endMicros = min((i + 1) * stepMicros, duration.inMicroseconds);
    final localCueStart = localStart + Duration(microseconds: startMicros);
    final localCueEnd = localStart + Duration(microseconds: endMicros);
    cues.add(
      WordCue(
        wordIndex: wordOffset + i,
        start: globalStart + Duration(microseconds: startMicros),
        end: globalStart + Duration(microseconds: endMicros),
        chunkIndex: chunkIndex,
        localStart: localCueStart,
        localEnd: localCueEnd,
      ),
    );
  }
  if (cues.isNotEmpty) {
    final last = cues.last;
    cues[cues.length - 1] = WordCue(
      wordIndex: last.wordIndex,
      start: last.start,
      end: globalStart + duration,
      chunkIndex: last.chunkIndex,
      localStart: last.localStart,
      localEnd: localStart + duration,
    );
  }
  return cues;
}

int wordIndexForPosition(Duration position, List<WordCue> cues) {
  if (cues.isEmpty) {
    return 0;
  }
  var low = 0;
  var high = cues.length - 1;
  while (low <= high) {
    final mid = low + ((high - low) >> 1);
    final cue = cues[mid];
    if (position < cue.start) {
      high = mid - 1;
    } else if (position >= cue.end) {
      low = mid + 1;
    } else {
      return cue.wordIndex;
    }
  }
  if (position < cues.first.start) {
    return cues.first.wordIndex;
  }
  return cues.last.wordIndex;
}

int wordIndexForChunkPosition({
  required int chunkIndex,
  required Duration position,
  required List<WordCue> cues,
}) {
  if (cues.isEmpty) {
    return 0;
  }
  final chunkCues = cues.where((cue) => cue.chunkIndex == chunkIndex).toList();
  if (chunkCues.isEmpty) {
    return wordIndexForPosition(position, cues);
  }
  for (final cue in chunkCues) {
    if (position >= cue.localStart && position < cue.localEnd) {
      return cue.wordIndex;
    }
  }
  if (position < chunkCues.first.localStart) {
    return chunkCues.first.wordIndex;
  }
  return chunkCues.last.wordIndex;
}

WordSeekTarget? seekTargetForWord(int wordIndex, List<WordCue> cues) {
  if (cues.isEmpty) {
    return null;
  }
  final clamped = wordIndex.clamp(cues.first.wordIndex, cues.last.wordIndex);
  for (final cue in cues) {
    if (cue.wordIndex == clamped) {
      return WordSeekTarget(
        position: cue.localStart,
        chunkIndex: cue.chunkIndex,
      );
    }
  }
  return WordSeekTarget(
    position: cues.last.localStart,
    chunkIndex: cues.last.chunkIndex,
  );
}

Duration estimateChunkDuration({
  required int chunkIndex,
  required List<int> chunkWordCounts,
  required Duration fallbackTotalDuration,
}) {
  final totalWords = chunkWordCounts.fold<int>(0, (sum, count) => sum + count);
  if (totalWords <= 0 || fallbackTotalDuration <= Duration.zero) {
    return const Duration(seconds: 15);
  }
  final safeIndex = chunkIndex.clamp(0, chunkWordCounts.length - 1);
  final estimatedMs = fallbackTotalDuration.inMilliseconds *
      chunkWordCounts[safeIndex] /
      totalWords;
  return Duration(milliseconds: estimatedMs.round().clamp(1000, 600000));
}
