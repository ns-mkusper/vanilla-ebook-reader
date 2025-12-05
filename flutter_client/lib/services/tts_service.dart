import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tts_flutter_client/api.dart' as bridge;

import '../services/llm_models.dart';
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
    this.llmModel = defaultLlmModel,
  });

  final VoiceSelection voice;
  final double rate;
  final String llmModel;

  TtsConfig copyWith({
    VoiceSelection? voice,
    double? rate,
    String? llmModel,
  }) {
    return TtsConfig(
      voice: voice ?? this.voice,
      rate: rate ?? this.rate,
      llmModel: llmModel ?? this.llmModel,
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

  void selectLlmModel(String model) {
    state = state.copyWith(llmModel: model);
  }

  void updateFromPrompt(String prompt) {
    final lower = prompt.toLowerCase();
    if (lower.contains('warm') || lower.contains('kind')) {
      _selectVoiceById('amy-medium');
    }
    if (lower.contains('energetic')) {
      _selectVoiceById(defaultVoiceId);
      updateRate(1.25);
    }
    if (lower.contains('slow')) {
      updateRate(0.85);
    }
  }

  void _selectVoiceById(String id) {
    final preset = voiceModelPresets.firstWhere((p) => p.id == id);
    selectVoice(
      VoiceSelection(
        id: preset.id,
        displayName: preset.label,
        backend: preset.backend,
      ),
    );
  }
}

final ttsServiceProvider = Provider<TtsService>((ref) {
  return TtsService(ref);
});

class TtsService {
  TtsService(this._ref) {
    _ref.onDispose(() => _positionSub?.cancel());
  }

  final Ref _ref;
  StreamSubscription<Duration>? _positionSub;

  Future<void> speak(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty) {
      return;
    }

    final repo = _ref.read(modelRepositoryProvider);
    final config = _ref.read(ttsConfigProvider);
    final notifier = _ref.read(ttsConfigProvider.notifier);
    final audioHandler = await _ref.read(audioHandlerProvider);

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
    final stream = bridge.streamAudio(text: text, request: request);

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
    final duration = await audioHandler.playPcm(
      pcmBytes,
      resolvedRate,
      cacheDirPath: cacheDir.path,
    );
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

const _fallbackSampleRate = 16000;
