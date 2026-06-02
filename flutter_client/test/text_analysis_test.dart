import 'package:flutter_test/flutter_test.dart';
import 'package:just_read_it/services/text_analysis.dart';

void main() {
  test('wordIndexForPosition uses cue windows with binary-search boundaries',
      () {
    final cues = buildWordCues(4, const Duration(seconds: 4));

    expect(wordIndexForPosition(Duration.zero, cues), 0);
    expect(wordIndexForPosition(const Duration(milliseconds: 999), cues), 0);
    expect(wordIndexForPosition(const Duration(seconds: 1), cues), 1);
    expect(wordIndexForPosition(const Duration(seconds: 3), cues), 3);
    expect(wordIndexForPosition(const Duration(seconds: 5), cues), 3);
  });

  test('chunked word cues use measured chunk durations for highlighting', () {
    final cues = buildChunkedWordCues(
      chunkWordCounts: const [2, 2],
      chunkDurations: const [Duration(seconds: 2), Duration(seconds: 6)],
      fallbackTotalDuration: const Duration(seconds: 8),
    );

    expect(cues, hasLength(4));
    expect(cues[0].wordIndex, 0);
    expect(cues[0].chunkIndex, 0);
    expect(cues[0].localStart, Duration.zero);
    expect(cues[1].localStart, const Duration(seconds: 1));
    expect(cues[2].wordIndex, 2);
    expect(cues[2].chunkIndex, 1);
    expect(cues[2].start, const Duration(seconds: 2));
    expect(cues[2].localStart, Duration.zero);
    expect(cues[3].localStart, const Duration(seconds: 3));

    expect(
      wordIndexForChunkPosition(
        chunkIndex: 1,
        position: const Duration(seconds: 4),
        cues: cues,
      ),
      3,
    );
  });

  test('seekTargetForWord returns chunk-local seek target', () {
    final cues = buildChunkedWordCues(
      chunkWordCounts: const [2, 3],
      chunkDurations: const [Duration(seconds: 2), Duration(seconds: 9)],
      fallbackTotalDuration: const Duration(seconds: 11),
    );

    final target = seekTargetForWord(4, cues);

    expect(target, isNotNull);
    expect(target!.chunkIndex, 1);
    expect(target.position, const Duration(seconds: 6));
  });
}
