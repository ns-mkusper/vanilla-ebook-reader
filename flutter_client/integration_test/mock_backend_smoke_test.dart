import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:tts_flutter_client/api.dart' as bridge;
import 'package:tts_flutter_client/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mock backend emits audible audio and plays back',
      (tester) async {
    await tester.runAsync(() async {
      await app.initializeTtsBridge();

      final request = bridge.EngineRequest(
        backend: bridge.EngineBackend.auto(modelPath: 'mock-orbit'),
        gainDb: null,
      );

      final samples = <int>[];
      int? sampleRate;

      await for (final chunk in bridge.streamAudio(
          text: 'Testing Orbit playback.', request: request)) {
        samples.addAll(chunk.pcm);
        sampleRate ??= chunk.sampleRate;
      }

      expect(sampleRate, isNotNull);
      expect(samples, isNotEmpty);

      final maxAmplitude = samples.fold<int>(0, (acc, value) {
        final absVal = value.abs();
        return max(acc, absVal);
      });

      // Anything under ~100 is near silence for 16-bit PCM; ensure we have real signal.
      expect(maxAmplitude, greaterThan(200));

      final wavFile = await _writeWav(samples, sampleRate!);
      final player = AudioPlayer();
      final completed = Completer<void>();
      late StreamSubscription<PlayerState> stateSub;
      stateSub = player.playerStateStream.listen((state) {
        if (!completed.isCompleted &&
            state.processingState == ProcessingState.completed) {
          completed.complete();
        }
      });

      try {
        await player.setAudioSource(AudioSource.uri(Uri.file(wavFile.path)));
        await player.play();
        await completed.future.timeout(const Duration(seconds: 5));
      } finally {
        await stateSub.cancel();
        await player.dispose();
        await wavFile.delete().catchError((_) {});
      }
    });
  });
}

Future<File> _writeWav(List<int> samples, int sampleRate) async {
  final bytes = BytesBuilder();
  for (final value in samples) {
    final clamped = value & 0xFFFF;
    bytes.add([clamped & 0xFF, (clamped >> 8) & 0xFF]);
  }
  final pcmBytes = bytes.takeBytes();
  final header = _buildWavHeader(
    dataLength: pcmBytes.length,
    sampleRate: sampleRate,
    bytesPerSample: 2,
    channels: 1,
  );
  final wavBytes = Uint8List(header.length + pcmBytes.length)
    ..setRange(0, header.length, header)
    ..setRange(header.length, header.length + pcmBytes.length, pcmBytes);
  final file = File('${Directory.systemTemp.path}/mock_orbit_test.wav');
  await file.writeAsBytes(wavBytes, flush: true);
  return file;
}

Uint8List _buildWavHeader({
  required int dataLength,
  required int sampleRate,
  required int bytesPerSample,
  required int channels,
}) {
  final chunkSize = 36 + dataLength;
  final byteRate = sampleRate * channels * bytesPerSample;
  final blockAlign = channels * bytesPerSample;
  final builder = BytesBuilder();

  void writeString(String value) =>
      builder.add(value.codeUnits.take(4).toList());
  void writeUint32(int value) {
    builder.add([
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ]);
  }

  void writeUint16(int value) {
    builder.add([
      value & 0xFF,
      (value >> 8) & 0xFF,
    ]);
  }

  writeString('RIFF');
  writeUint32(chunkSize);
  writeString('WAVE');
  writeString('fmt ');
  writeUint32(16);
  writeUint16(1);
  writeUint16(channels);
  writeUint32(sampleRate);
  writeUint32(byteRate);
  writeUint16(blockAlign);
  writeUint16(bytesPerSample * 8);
  writeString('data');
  writeUint32(dataLength);
  return Uint8List.fromList(builder.takeBytes());
}
