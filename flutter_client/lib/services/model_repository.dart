import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final modelRepositoryProvider =
    Provider<ModelRepository>((_) => ModelRepository());

enum TtsEngineBackend { androidSystem, fliteClassic, piper }

class VoiceModelPreset {
  const VoiceModelPreset({
    required this.id,
    required this.label,
    required this.description,
    required this.backend,
    this.assetModelPath,
    this.assetConfigPath,
    this.androidEngine,
    this.androidVoiceName,
    this.androidVoiceLocale = 'en-US',
  });

  final String id;
  final String label;
  final String description;
  final TtsEngineBackend backend;
  final String? assetModelPath;
  final String? assetConfigPath;
  final String? androidEngine;
  final String? androidVoiceName;
  final String androidVoiceLocale;
}

@immutable
class VoiceSelection {
  const VoiceSelection({
    required this.id,
    required this.displayName,
    required this.backend,
    this.modelPath,
    this.configPath,
    this.androidEngine,
    this.androidVoiceName,
    this.androidVoiceLocale = 'en-US',
  });

  final String id;
  final String displayName;
  final TtsEngineBackend backend;
  final String? modelPath;
  final String? configPath;
  final String? androidEngine;
  final String? androidVoiceName;
  final String androidVoiceLocale;

  VoiceSelection copyWith({
    String? modelPath,
    String? configPath,
    String? androidEngine,
    String? androidVoiceName,
    String? androidVoiceLocale,
  }) {
    return VoiceSelection(
      id: id,
      displayName: displayName,
      backend: backend,
      modelPath: modelPath ?? this.modelPath,
      configPath: configPath ?? this.configPath,
      androidEngine: androidEngine ?? this.androidEngine,
      androidVoiceName: androidVoiceName ?? this.androidVoiceName,
      androidVoiceLocale: androidVoiceLocale ?? this.androidVoiceLocale,
    );
  }

  @override
  int get hashCode => Object.hash(
        id,
        displayName,
        backend,
        modelPath,
        configPath,
        androidEngine,
        androidVoiceName,
        androidVoiceLocale,
      );

  @override
  bool operator ==(Object other) {
    return other is VoiceSelection &&
        id == other.id &&
        displayName == other.displayName &&
        backend == other.backend &&
        other.modelPath == modelPath &&
        other.configPath == configPath &&
        other.androidEngine == androidEngine &&
        other.androidVoiceName == androidVoiceName &&
        other.androidVoiceLocale == androidVoiceLocale;
  }
}

const defaultVoiceId = String.fromEnvironment(
  'JRI_DEFAULT_VOICE_ID',
  defaultValue: 'flite-classic',
);

const voiceModelPresets = <VoiceModelPreset>[
  VoiceModelPreset(
    id: 'android-male',
    label: 'Android Male Voice',
    description:
        'Prefers a lower-pitched male English system voice, then plays generated audio with the Just Read It media player.',
    backend: TtsEngineBackend.androidSystem,
    androidVoiceName: 'en-us-x-iom-local',
  ),
  VoiceModelPreset(
    id: 'android-system',
    label: 'Android Default Voice',
    description:
        'Uses the device default TTS engine and voice, then plays generated audio with the Just Read It media player.',
    backend: TtsEngineBackend.androidSystem,
  ),
  VoiceModelPreset(
    id: 'flite-classic',
    label: 'Motorola Male (Flite)',
    description:
        'Bundled offline Flite KAL male voice. No separate Android TTS engine install required.',
    backend: TtsEngineBackend.fliteClassic,
    androidEngine: 'edu.cmu.cs.speech.tts.flite',
  ),
];

class ModelRepository {
  final Map<String, Future<VoiceSelection>> _inflight = {};

  Future<VoiceSelection> ensureSelectionReady(VoiceSelection selection) async {
    if (selection.backend != TtsEngineBackend.piper) {
      if (selection.modelPath != null) {
        return selection;
      }
      final preset = voiceModelPresets.firstWhere((p) => p.id == selection.id);
      return _selectionFromPreset(preset, modelPath: preset.id);
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
      return _selectionFromPreset(preset, modelPath: preset.id);
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

  VoiceSelection _selectionFromPreset(
    VoiceModelPreset preset, {
    String? modelPath,
  }) {
    return VoiceSelection(
      id: preset.id,
      displayName: preset.label,
      backend: preset.backend,
      modelPath: modelPath,
      androidEngine: preset.androidEngine,
      androidVoiceName: preset.androidVoiceName,
      androidVoiceLocale: preset.androidVoiceLocale,
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
