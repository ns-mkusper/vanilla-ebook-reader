import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_flutter_client/api.dart' as bridge;

import 'audio_handler.dart';

final ttsConfigProvider =
    StateNotifierProvider<TtsConfigNotifier, TtsConfig>((ref) {
  return TtsConfigNotifier(const TtsConfig());
});

final currentWordIndexProvider = StateProvider<int>((ref) => 0);

class TtsConfig {
  const TtsConfig({this.modelPath, this.rate = 1.0});

  final String? modelPath;
  final double rate;

  TtsConfig copyWith({String? modelPath, double? rate}) => TtsConfig(
        modelPath: modelPath ?? this.modelPath,
        rate: rate ?? this.rate,
      );
}

class TtsConfigNotifier extends StateNotifier<TtsConfig> {
  TtsConfigNotifier(super.state);

  void selectModel(String path) {
    state = state.copyWith(modelPath: path);
  }

  void updateRate(double value) {
    state = state.copyWith(rate: value);
  }

  void updateFromPrompt(String prompt) {
    // Placeholder: inspect prompt keywords and decide on a model.
    if (prompt.toLowerCase().contains('spooky')) {
      state = state.copyWith(modelPath: 'assets/models/en_us_amy_medium.onnx');
    }
  }
}

final ttsServiceProvider = Provider<TtsService>((ref) {
  return TtsService(ref);
});

class TtsService {
  TtsService(this._ref);

  final Ref _ref;

  Future<void> speak(String text) async {
    final config = _ref.read(ttsConfigProvider);
    final audioHandler = await _ref.read(audioHandlerProvider);

    final backend = bridge.EngineBackend.auto(
      modelPath: config.modelPath ?? _defaultModelPath,
    );
    final request = bridge.EngineRequest(
      backend: backend,
      gainDb: null,
    );

    final stream = bridge.streamAudio(
      text: text,
      request: request,
    );

    final buffer = BytesBuilder();
    int? sampleRate;

    await for (final chunk in stream) {
      final pcmView = chunk.pcm.buffer.asUint8List();
      buffer.add(pcmView);
      sampleRate ??= chunk.sampleRate;
      _ref.read(currentWordIndexProvider.notifier).state =
          chunk.startTextIdx.toInt();
    }

    final collected = buffer.takeBytes();
    await audioHandler.playPcm(collected, sampleRate ?? 16000);
  }
}

const _defaultModelPath = 'assets/models/en_us_amy_medium.onnx';
