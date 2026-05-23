import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_read_it/api.dart' as bridge;

import '../services/model_repository.dart';
import '../services/text_analysis.dart';
import 'audio_handler.dart';

final ttsConfigProvider =
    StateNotifierProvider<TtsConfigNotifier, TtsConfig>((ref) {
  return TtsConfigNotifier();
});

final currentWordIndexProvider = StateProvider<int>((ref) => 0);
final wordBoundariesProvider =
    StateProvider<List<TextWordBoundary>>((ref) => const []);
final wordCuesProvider = StateProvider<List<WordCue>>((ref) => const []);

class TtsConfig {
  const TtsConfig({
    required this.voice,
    this.rate = 1.0,
    this.pitch = 1.0,
  });

  final VoiceSelection voice;
  final double rate;
  final double pitch;
  TtsConfig copyWith({
    VoiceSelection? voice,
    double? rate,
    double? pitch,
  }) {
    return TtsConfig(
      voice: voice ?? this.voice,
      rate: rate ?? this.rate,
      pitch: pitch ?? this.pitch,
    );
  }
}

class TtsConfigNotifier extends StateNotifier<TtsConfig> {
  TtsConfigNotifier()
      : super(
          TtsConfig(
            voice: () {
              final preset =
                  voiceModelPresets.firstWhere((p) => p.id == defaultVoiceId);
              return VoiceSelection(
                id: preset.id,
                displayName: preset.label,
                backend: preset.backend,
                androidEngine: preset.androidEngine,
              );
            }(),
          ),
        );

  void selectVoice(VoiceSelection selection) {
    state = state.copyWith(voice: selection);
  }

  void hydrateVoice(VoiceSelection selection) {
    selectVoice(selection);
  }

  void updateRate(double value) {
    state = state.copyWith(rate: value);
  }

  void updatePitch(double value) {
    state = state.copyWith(pitch: value);
  }
}

final ttsServiceProvider = Provider<SpeechService>((ref) {
  return TtsService(ref);
});

abstract class SpeechService {
  Future<void> speak(String rawText);
}

class TtsService implements SpeechService {
  TtsService(this._ref) {
    _ref.onDispose(() => _positionSub?.cancel());
  }

  final Ref _ref;
  StreamSubscription<Duration>? _positionSub;

  @override
  Future<void> speak(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty) {
      return;
    }

    final repo = _ref.read(modelRepositoryProvider);
    final config = _ref.read(ttsConfigProvider);
    final notifier = _ref.read(ttsConfigProvider.notifier);

    var voice = await repo.ensureSelectionReady(config.voice);
    notifier.hydrateVoice(voice);

    switch (voice.backend) {
      case TtsEngineBackend.androidSystem:
      case TtsEngineBackend.fliteClassic:
        await _speakWithPlatformTts(text, voice, config);
      case TtsEngineBackend.piper:
        await _speakWithRustPiper(text, voice, config);
    }
  }

  Future<void> _speakWithPlatformTts(
    String text,
    VoiceSelection voice,
    TtsConfig config,
  ) async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      throw UnsupportedError(
          'System TTS file synthesis is not available here.');
    }

    final cacheDir = await getTemporaryDirectory();
    final generated = File(
      '${cacheDir.path}/just_read_it_system_tts_${DateTime.now().microsecondsSinceEpoch}.wav',
    );

    final flutterTts = FlutterTts();
    await flutterTts.awaitSynthCompletion(true);
    await flutterTts.setLanguage(voice.androidVoiceLocale);
    await flutterTts.setVolume(1.0);
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setPitch(config.pitch.clamp(0.5, 2.0));

    await _configurePlatformVoice(flutterTts, voice);

    final maxInputLength = await _platformMaxInputLength(flutterTts);
    final chunks = splitPlatformTtsText(text, maxChars: maxInputLength);
    final chunkFiles = <File>[];
    try {
      for (var index = 0; index < chunks.length; index++) {
        final chunkFile = chunks.length == 1
            ? generated
            : File(
                '${cacheDir.path}/just_read_it_tts_chunk_${DateTime.now().microsecondsSinceEpoch}_$index.wav');
        final result = await flutterTts.synthesizeToFile(
          chunks[index],
          chunkFile.path,
          true,
        );
        if (!await chunkFile.exists()) {
          throw StateError(
            'System TTS did not create ${chunkFile.path} (result=$result).',
          );
        }
        final size = await chunkFile.length();
        if (size <= 44) {
          throw StateError('System TTS produced empty WAV chunk $index.');
        }
        chunkFiles.add(chunkFile);
      }
      if (chunkFiles.length > 1) {
        await stitchWavFiles(chunkFiles, generated);
      }
    } finally {
      for (final file in chunkFiles) {
        if (file.path != generated.path && await file.exists()) {
          await file.delete();
        }
      }
    }

    final duration = await _wavDuration(generated);
    final audioHandler = await _ref.read(audioHandlerProvider);
    await audioHandler.playFile(
      generated,
      duration: duration,
      speed: config.rate,
    );
    _attachTextTimeline(text, duration, audioHandler);
  }

  Future<void> _speakWithRustPiper(
    String text,
    VoiceSelection voice,
    TtsConfig config,
  ) async {
    final backend = bridge.EngineBackend.piper(
      bridge.PiperBackendConfig(
        modelPath: voice.modelPath!,
        configPath: voice.configPath,
        speaker: null,
        sampleRate: null,
      ),
    );

    final request = bridge.EngineRequest(backend: backend, gainDb: null);
    final stream = bridge.streamAudio(text: text, request: request).timeout(
          const Duration(seconds: 2),
          onTimeout: (sink) => sink.close(),
        );

    final buffer = BytesBuilder();
    int? sampleRate;
    var chunkCount = 0;
    var totalSamples = 0;

    try {
      await for (final chunk in stream) {
        final pcmView = chunk.pcm.buffer.asUint8List(
          chunk.pcm.offsetInBytes,
          chunk.pcm.lengthInBytes,
        );
        buffer.add(pcmView);
        sampleRate ??= chunk.sampleRate;
        chunkCount++;
        totalSamples += chunk.pcm.length;
      }
    } catch (err, stack) {
      debugPrint('TTS stream failed: $err');
      debugPrintStack(stackTrace: stack);
      _ref.read(currentWordIndexProvider.notifier).state = 0;
      rethrow;
    }

    final pcmBytes = buffer.takeBytes();
    if (totalSamples == 0) {
      throw StateError(
        'Engine ${voice.id} produced no audio (chunks=$chunkCount).',
      );
    }
    final resolvedRate = sampleRate ?? _fallbackSampleRate;
    debugPrint(
      'Synthesized ${pcmBytes.length} bytes ($totalSamples samples) at '
      '${resolvedRate}Hz using voice ${voice.id} (${voice.backend}).',
    );

    final audioHandler = await _ref.read(audioHandlerProvider);
    final duration = await audioHandler.playPcm(
      pcmBytes,
      resolvedRate,
      speed: config.rate,
    );
    _attachTextTimeline(text, duration, audioHandler);
  }

  Future<Duration> _wavDuration(File file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length >= 44 && String.fromCharCodes(bytes.take(4)) == 'RIFF') {
      final data = ByteData.sublistView(bytes);
      final byteRate = data.getUint32(28, Endian.little);
      final dataLength = data.getUint32(40, Endian.little);
      if (byteRate > 0) {
        return Duration(
          milliseconds: (dataLength / byteRate * 1000).round(),
        );
      }
    }
    return const Duration(seconds: 1);
  }

  void _attachTextTimeline(
    String text,
    Duration duration,
    TtsAudioHandler audioHandler,
  ) {
    final boundaries = computeWordBoundaries(text);
    _ref.read(wordBoundariesProvider.notifier).state = boundaries;
    final cues = buildWordCues(boundaries.length, duration);
    _ref.read(wordCuesProvider.notifier).state = cues;
    _ref.read(currentWordIndexProvider.notifier).state = 0;
    _attachTimeline(audioHandler, cues);
  }

  void _attachTimeline(TtsAudioHandler handler, List<WordCue> cues) {
    _positionSub?.cancel();
    if (cues.isEmpty) {
      return;
    }
    _positionSub = handler.positionStream().listen((position) {
      final index = wordIndexForPosition(position, cues);
      _ref.read(currentWordIndexProvider.notifier).state = index;
    });
  }
}

Future<void> _configurePlatformVoice(
  FlutterTts flutterTts,
  VoiceSelection voice,
) async {
  if (voice.backend == TtsEngineBackend.fliteClassic) {
    if (voice.androidEngine == null || !Platform.isAndroid) {
      throw StateError('Classic Flite requires an Android Flite TTS engine.');
    }
    try {
      await flutterTts.setEngine(voice.androidEngine!);
    } catch (err) {
      throw StateError(
        'Classic Flite is unavailable. Install a Flite Android TTS engine or select another voice. ($err)',
      );
    }
    return;
  }

  if (voice.androidVoiceName == null) return;
  final selected = await _selectAndroidVoice(flutterTts, voice);
  if (!selected) {
    debugPrint(
      'Preferred Android voice ${voice.androidVoiceName} unavailable; using default engine voice.',
    );
  }
}

Future<bool> _selectAndroidVoice(
  FlutterTts flutterTts,
  VoiceSelection voice,
) async {
  final preferredName = voice.androidVoiceName;
  if (preferredName == null || preferredName.isEmpty) return false;
  final selectedVoice = <String, String>{
    'name': preferredName,
    'locale': voice.androidVoiceLocale,
  };
  try {
    await flutterTts.setVoice(selectedVoice);
    debugPrint(
      'JRI_ANDROID_VOICE_SELECTED=${selectedVoice['name']} '
      '${selectedVoice['locale']}',
    );
    return true;
  } catch (err) {
    debugPrint(
      'Preferred Android voice ${voice.androidVoiceName} unavailable; '
      'using default engine voice. $err',
    );
    return false;
  }
}

Future<int> _platformMaxInputLength(FlutterTts flutterTts) async {
  if (Platform.isAndroid) {
    final maxLength = await flutterTts.getMaxSpeechInputLength;
    if (maxLength != null && maxLength > 0) {
      return maxLength.clamp(500, _platformChunkHardCap).toInt();
    }
  }
  return _platformChunkHardCap;
}

@visibleForTesting
List<String> splitPlatformTtsText(
  String rawText, {
  int maxChars = _platformChunkHardCap,
}) {
  final normalized = rawText
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();
  if (normalized.isEmpty) return const [];

  final safeMax = maxChars.clamp(200, _platformChunkHardCap).toInt();
  final chunks = <String>[];
  final buffer = StringBuffer();

  void flush() {
    final chunk = buffer.toString().trim();
    if (chunk.isNotEmpty) chunks.add(chunk);
    buffer.clear();
  }

  void appendSegment(String segment) {
    final trimmed = segment.trim();
    if (trimmed.isEmpty) return;
    if (trimmed.length > safeMax) {
      flush();
      for (var start = 0; start < trimmed.length; start += safeMax) {
        final end = (start + safeMax).clamp(0, trimmed.length).toInt();
        chunks.add(trimmed.substring(start, end).trim());
      }
      return;
    }
    final pendingLength = buffer.isEmpty
        ? trimmed.length
        : buffer.length + _chunkSeparator.length + trimmed.length;
    if (pendingLength > safeMax) flush();
    if (buffer.isNotEmpty) buffer.write(_chunkSeparator);
    buffer.write(trimmed);
  }

  final paragraphs = normalized.split(RegExp(r'\n{2,}'));
  for (final paragraph in paragraphs) {
    final sentences = paragraph
        .splitMapJoin(
          RegExp(r'(?<=[.!?])\s+'),
          onMatch: (_) => '\u{1f}',
          onNonMatch: (text) => text,
        )
        .split('\u{1f}');
    for (final sentence in sentences) {
      appendSegment(sentence);
    }
  }
  flush();
  return chunks;
}

@visibleForTesting
Future<File> stitchWavFiles(List<File> inputs, File output) async {
  if (inputs.isEmpty) {
    throw ArgumentError.value(inputs, 'inputs', 'must not be empty');
  }
  final pcmParts = <Uint8List>[];
  int? sampleRate;
  int? channels;
  int? bitsPerSample;
  var totalDataLength = 0;

  for (final input in inputs) {
    final bytes = await input.readAsBytes();
    final info = _parsePcmWav(bytes, input.path);
    sampleRate ??= info.sampleRate;
    channels ??= info.channels;
    bitsPerSample ??= info.bitsPerSample;
    if (info.sampleRate != sampleRate ||
        info.channels != channels ||
        info.bitsPerSample != bitsPerSample) {
      throw StateError('Cannot stitch WAV files with different formats.');
    }
    pcmParts.add(info.pcmBytes);
    totalDataLength += info.pcmBytes.length;
  }

  final out = BytesBuilder(copy: false);
  out.add(_wavHeader(
    dataLength: totalDataLength,
    sampleRate: sampleRate!,
    channels: channels!,
    bitsPerSample: bitsPerSample!,
  ));
  for (final part in pcmParts) {
    out.add(part);
  }
  await output.writeAsBytes(out.takeBytes(), flush: true);
  return output;
}

_PcmWav _parsePcmWav(Uint8List bytes, String label) {
  if (bytes.length < 44 || ascii.decode(bytes.sublist(0, 4)) != 'RIFF') {
    throw StateError('$label is not a RIFF WAV file.');
  }
  if (ascii.decode(bytes.sublist(8, 12)) != 'WAVE') {
    throw StateError('$label is not a WAVE file.');
  }
  final data = ByteData.sublistView(bytes);
  final channels = data.getUint16(22, Endian.little);
  final sampleRate = data.getUint32(24, Endian.little);
  final bitsPerSample = data.getUint16(34, Endian.little);

  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunkId = ascii.decode(bytes.sublist(offset, offset + 4));
    final chunkLength = data.getUint32(offset + 4, Endian.little);
    final chunkStart = offset + 8;
    final chunkEnd = chunkStart + chunkLength;
    if (chunkEnd > bytes.length) {
      throw StateError('$label has a truncated $chunkId chunk.');
    }
    if (chunkId == 'data') {
      return _PcmWav(
        sampleRate: sampleRate,
        channels: channels,
        bitsPerSample: bitsPerSample,
        pcmBytes: Uint8List.fromList(bytes.sublist(chunkStart, chunkEnd)),
      );
    }
    offset = chunkEnd + (chunkLength.isOdd ? 1 : 0);
  }
  throw StateError('$label has no data chunk.');
}

Uint8List _wavHeader({
  required int dataLength,
  required int sampleRate,
  required int channels,
  required int bitsPerSample,
}) {
  final bytesPerSample = bitsPerSample ~/ 8;
  final header = ByteData(44);
  header.setUint32(0, 0x52494646, Endian.big);
  header.setUint32(4, 36 + dataLength, Endian.little);
  header.setUint32(8, 0x57415645, Endian.big);
  header.setUint32(12, 0x666d7420, Endian.big);
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * channels * bytesPerSample, Endian.little);
  header.setUint16(32, channels * bytesPerSample, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  header.setUint32(36, 0x64617461, Endian.big);
  header.setUint32(40, dataLength, Endian.little);
  return header.buffer.asUint8List();
}

class _PcmWav {
  const _PcmWav({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.pcmBytes,
  });

  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final Uint8List pcmBytes;
}

const _fallbackSampleRate = 16000;
const _platformChunkHardCap = 3200;
const _chunkSeparator = '\n\n';
