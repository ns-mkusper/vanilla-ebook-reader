import 'package:flutter_test/flutter_test.dart';
import 'package:tts_flutter_client/services/text_analysis.dart';

void main() {
  const iterations = 200;
  final sampleText = _buildSampleText(wordCount: 4000);

  group('text analysis performance', () {
    test('computeWordBoundaries averages under 1500µs for 4k words', () {
      final sw = Stopwatch()..start();
      for (var i = 0; i < iterations; i++) {
        final result = computeWordBoundaries(sampleText);
        expect(result.length, greaterThan(2000));
      }
      sw.stop();
      final perIterationUs = sw.elapsedMicroseconds / iterations;
      expect(
        perIterationUs,
        lessThan(1500),
        reason:
            'Word boundary detection should remain near-linear; saw ${perIterationUs.toStringAsFixed(2)}µs.',
      );
    });

    test('buildWordCues stays under 1200µs for 4k words', () {
      final boundaries = computeWordBoundaries(sampleText);
      final sw = Stopwatch()..start();
      for (var i = 0; i < iterations; i++) {
        final cues = buildWordCues(boundaries.length, const Duration(seconds: 240));
        expect(cues, isNotEmpty);
      }
      sw.stop();
      final perIterationUs = sw.elapsedMicroseconds / iterations;
      expect(
        perIterationUs,
        lessThan(1200),
        reason:
            'Cue building should remain linear in the word count; saw ${perIterationUs.toStringAsFixed(2)}µs.',
      );
    });

    test('wordIndexForPosition resolves under 800µs', () {
      final cues = buildWordCues(4000, const Duration(minutes: 5));
      final sw = Stopwatch()..start();
      for (var i = 0; i < iterations; i++) {
        final idx = wordIndexForPosition(
          Duration(milliseconds: i % 300 * 100),
          cues,
        );
        expect(idx, inInclusiveRange(0, 3999));
      }
      sw.stop();
      final perIterationUs = sw.elapsedMicroseconds / iterations;
      expect(
        perIterationUs,
        lessThan(800),
        reason:
            'Index lookup should stay near-constant; saw ${perIterationUs.toStringAsFixed(2)}µs.',
      );
    });
  });
}

String _buildSampleText({required int wordCount}) {
  const seed = 'time travelers whisper through neon-lit alleyways';
  final buffer = StringBuffer();
  while (buffer.length < wordCount * 6) {
    buffer.write(seed);
    buffer.write(' ');
  }
  return buffer.toString();
}
