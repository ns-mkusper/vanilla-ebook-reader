import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
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
  });

  final VoiceSelection voice;
  final double rate;
  TtsConfig copyWith({
    VoiceSelection? voice,
    double? rate,
  }) {
    return TtsConfig(
      voice: voice ?? this.voice,
      rate: rate ?? this.rate,
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

    final backend = switch (voice.backend) {
      TtsEngineBackend.mock => bridge.EngineBackend.auto(
          modelPath: voice.modelPath ?? voice.id,
        ),
      TtsEngineBackend.piper => bridge.EngineBackend.piper(
          bridge.PiperBackendConfig(
            modelPath: voice.modelPath!,
            configPath: voice.configPath,
            speaker: null,
            sampleRate: null,
          ),
        ),
    };

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

    final cacheDir = await getTemporaryDirectory();
    await _exportTtsWavIfRequested(
      pcmBytes,
      resolvedRate,
      cacheDirPath: cacheDir.path,
    );
    final audioHandler = await _ref.read(audioHandlerProvider);
    final duration = await audioHandler.playPcm(
      pcmBytes,
      resolvedRate,
    );
    final boundaries = computeWordBoundaries(text);
    _ref.read(wordBoundariesProvider.notifier).state = boundaries;
    final cues = buildWordCues(boundaries.length, duration);
    _ref.read(wordCuesProvider.notifier).state = cues;
    _ref.read(currentWordIndexProvider.notifier).state = 0;
    _attachTimeline(audioHandler, cues);
  }

  Future<void> _exportTtsWavIfRequested(
    Uint8List pcmBytes,
    int sampleRate, {
    required String cacheDirPath,
  }) async {
    const shouldExport = bool.fromEnvironment('JRI_EXPORT_TTS_WAV');
    if (!shouldExport) {
      return;
    }
    final file = File('$cacheDirPath/just_read_it_voice_sample.wav');
    await file.writeAsBytes(_wavBytes(pcmBytes, sampleRate), flush: true);
    debugPrint('JRI_TTS_WAV_PATH=${file.path}');
    debugPrint('JRI_TTS_WAV_READY');
  }

  Uint8List _wavBytes(Uint8List pcmBytes, int sampleRate) {
    final header = ByteData(44);
    header.setUint32(0, 0x52494646, Endian.big); // RIFF
    header.setUint32(4, 36 + pcmBytes.length, Endian.little);
    header.setUint32(8, 0x57415645, Endian.big); // WAVE
    header.setUint32(12, 0x666d7420, Endian.big); // fmt
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint32(36, 0x64617461, Endian.big); // data
    header.setUint32(40, pcmBytes.length, Endian.little);
    return Uint8List(44 + pcmBytes.length)
      ..setRange(0, 44, header.buffer.asUint8List())
      ..setRange(44, 44 + pcmBytes.length, pcmBytes);
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

const _fallbackSampleRate = 16000;
