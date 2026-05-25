import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_read_it/services/tts_service.dart';

void main() {
  test('splits long markdown into bounded platform TTS chunks without loss',
      () async {
    final fixture = await File('test/fixtures/long_markdown_fixture.md').readAsString();
    final chunks = splitPlatformTtsText(fixture, maxChars: 900);

    expect(fixture.length, greaterThan(8000));
    expect(chunks.length, greaterThan(8));
    expect(chunks.every((chunk) => chunk.length <= 900), isTrue);
    expect(chunks.join('\n\n'), contains('What does long-form markdown fixture mean'));
    expect(chunks.join('\n\n'), contains('See you at the end'));
    expect(chunks.join('\n\n').replaceAll(RegExp(r'\s+'), ' '),
        contains('Naota projects his feelings of abandonment onto Haruko'));
  });

  test('stitches platform WAV chunks into one valid PCM WAV', () async {
    final dir = await Directory.systemTemp.createTemp('jri_wav_stitch_');
    addTearDown(() => dir.delete(recursive: true));

    final first = File('${dir.path}/first.wav');
    final second = File('${dir.path}/second.wav');
    final output = File('${dir.path}/out.wav');
    await first.writeAsBytes(_wav([100, -100, 200, -200]));
    await second.writeAsBytes(_wav([300, -300]));

    await stitchWavFiles([first, second], output);
    final bytes = await output.readAsBytes();
    final data = ByteData.sublistView(bytes);

    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(data.getUint16(22, Endian.little), 1);
    expect(data.getUint32(24, Endian.little), 22050);
    expect(data.getUint16(34, Endian.little), 16);
    expect(data.getUint32(40, Endian.little), 12);
    expect(data.getInt16(44, Endian.little), 100);
    expect(data.getInt16(52, Endian.little), 300);
  });
}

Uint8List _wav(List<int> samples) {
  final pcm = Uint8List(samples.length * 2);
  final pcmData = ByteData.sublistView(pcm);
  for (var i = 0; i < samples.length; i++) {
    pcmData.setInt16(i * 2, samples[i], Endian.little);
  }
  final header = ByteData(44);
  header.setUint32(0, 0x52494646, Endian.big);
  header.setUint32(4, 36 + pcm.length, Endian.little);
  header.setUint32(8, 0x57415645, Endian.big);
  header.setUint32(12, 0x666d7420, Endian.big);
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, 22050, Endian.little);
  header.setUint32(28, 44100, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  header.setUint32(36, 0x64617461, Endian.big);
  header.setUint32(40, pcm.length, Endian.little);
  return Uint8List(44 + pcm.length)
    ..setRange(0, 44, header.buffer.asUint8List())
    ..setRange(44, 44 + pcm.length, pcm);
}
