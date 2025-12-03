import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final modelRepositoryProvider =
    Provider<ModelRepository>((_) => ModelRepository());

enum TtsEngineBackend { mock, piper }

class VoiceModelPreset {
  const VoiceModelPreset({
    required this.id,
    required this.label,
    required this.description,
    required this.backend,
    this.assetModelPath,
    this.assetConfigPath,
  });

  final String id;
  final String label;
  final String description;
  final TtsEngineBackend backend;
  final String? assetModelPath;
  final String? assetConfigPath;
}

@immutable
class VoiceSelection {
  const VoiceSelection({
    required this.id,
    required this.displayName,
    required this.backend,
    this.modelPath,
    this.configPath,
  });

  final String id;
  final String displayName;
  final TtsEngineBackend backend;
  final String? modelPath;
  final String? configPath;

  VoiceSelection copyWith({
    String? modelPath,
    String? configPath,
  }) {
    return VoiceSelection(
      id: id,
      displayName: displayName,
      backend: backend,
      modelPath: modelPath ?? this.modelPath,
      configPath: configPath ?? this.configPath,
    );
  }

  @override
  int get hashCode =>
      Object.hash(id, displayName, backend, modelPath, configPath);

  @override
  bool operator ==(Object other) {
    return other is VoiceSelection &&
        id == other.id &&
        displayName == other.displayName &&
        backend == other.backend &&
        other.modelPath == modelPath &&
        other.configPath == configPath;
  }
}

const defaultVoiceId = 'mock-orbit';

const voiceModelPresets = <VoiceModelPreset>[
  VoiceModelPreset(
    id: 'mock-orbit',
    label: 'Orbit (procedural)',
    description: 'Fast synthetic voice useful for rapid iteration.',
    backend: TtsEngineBackend.mock,
  ),
  VoiceModelPreset(
    id: 'amy-medium',
    label: 'Amy · en-US · medium',
    description: 'Bundled Piper voice (22.05 kHz, female).',
    backend: TtsEngineBackend.piper,
    assetModelPath: 'assets/models/en_us_amy_medium.onnx',
    assetConfigPath: 'assets/models/en_us_amy_medium.json',
  ),
];

class ModelRepository {
  final Map<String, Future<VoiceSelection>> _inflight = {};

  Future<VoiceSelection> ensureSelectionReady(VoiceSelection selection) async {
    if (selection.backend != TtsEngineBackend.piper) {
      return selection;
    }
    if (selection.modelPath != null && selection.configPath != null) {
      return selection;
    }
    final preset = voiceModelPresets.firstWhere((p) => p.id == selection.id);
    return ensurePresetReady(preset);
  }

  Future<VoiceSelection> ensurePresetReady(VoiceModelPreset preset) {
    final existing = _inflight[preset.id];
    if (existing != null) {
      return existing;
    }
    final future = _materialize(preset);
    _inflight[preset.id] = future;
    return future.whenComplete(() {
      _inflight.remove(preset.id);
    });
  }

  Future<VoiceSelection> _materialize(VoiceModelPreset preset) async {
    if (preset.backend != TtsEngineBackend.piper) {
      return VoiceSelection(
        id: preset.id,
        displayName: preset.label,
        backend: preset.backend,
      );
    }
    final modelAsset = preset.assetModelPath;
    final configAsset = preset.assetConfigPath;
    if (modelAsset == null || configAsset == null) {
      throw StateError('Preset ${preset.id} is missing bundled assets.');
    }

    final supportDir = await getApplicationSupportDirectory();
    final voiceDir = Directory(p.join(supportDir.path, 'voices', preset.id));
    if (!voiceDir.existsSync()) {
      voiceDir.createSync(recursive: true);
    }

    final modelFile = await _copyAssetIfNeeded(modelAsset, voiceDir);
    final configFile = await _copyAssetIfNeeded(configAsset, voiceDir);

    return VoiceSelection(
      id: preset.id,
      displayName: preset.label,
      backend: preset.backend,
      modelPath: modelFile.path,
      configPath: configFile.path,
    );
  }

  Future<File> _copyAssetIfNeeded(String assetPath, Directory voiceDir) async {
    final filename = p.basename(assetPath);
    final file = File(p.join(voiceDir.path, filename));
    if (await file.exists()) {
      return file;
    }
    final data = await rootBundle.load(assetPath);
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return file;
  }
}
