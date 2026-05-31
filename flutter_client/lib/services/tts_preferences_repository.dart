import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'document_repository.dart';

final ttsPreferencesRepositoryProvider =
    Provider<TtsPreferencesRepository>((ref) {
  final directory = ref.read(documentDirectoryProvider).valueOrNull;
  return TtsPreferencesRepository(directory: directory);
});

@immutable
class VoicePlaybackPreference {
  const VoicePlaybackPreference({
    this.rate = 1.0,
    this.pitch = 1.0,
  });

  final double rate;
  final double pitch;

  VoicePlaybackPreference copyWith({double? rate, double? pitch}) {
    return VoicePlaybackPreference(
      rate: rate ?? this.rate,
      pitch: pitch ?? this.pitch,
    );
  }

  Map<String, Object> toJson() => {
        'rate': rate,
        'pitch': pitch,
      };

  static VoicePlaybackPreference fromJson(Object? value) {
    if (value is! Map) {
      return const VoicePlaybackPreference();
    }
    return VoicePlaybackPreference(
      rate: _readDouble(value['rate'], fallback: 1.0).clamp(0.5, 3.0),
      pitch: _readDouble(value['pitch'], fallback: 1.0).clamp(0.7, 1.4),
    );
  }

  static double _readDouble(Object? value, {required double fallback}) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }
}

class TtsPreferencesRepository {
  TtsPreferencesRepository({Directory? directory}) : _directory = directory;

  final Directory? _directory;

  static const fileName = 'voice_preferences.json';

  Future<Map<String, VoicePlaybackPreference>> loadPreferences() async {
    final file = await _preferencesFile();
    if (!await file.exists()) {
      return const {};
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      return const {};
    }
    return decoded.map((key, value) {
      return MapEntry(
        key.toString(),
        VoicePlaybackPreference.fromJson(value),
      );
    });
  }

  Future<void> savePreference(
    String voiceId,
    VoicePlaybackPreference preference,
  ) async {
    final preferences = Map<String, VoicePlaybackPreference>.from(
      await loadPreferences(),
    );
    preferences[voiceId] = preference;
    await savePreferences(preferences);
  }

  Future<void> savePreferences(
    Map<String, VoicePlaybackPreference> preferences,
  ) async {
    final file = await _preferencesFile();
    final encoded = preferences.map(
      (key, value) => MapEntry(key, value.toJson()),
    );
    await file
        .writeAsString(const JsonEncoder.withIndent('  ').convert(encoded));
  }

  Future<File> _preferencesFile() async {
    final directory = await _ensureDirectory();
    return File(p.join(directory.path, fileName));
  }

  Future<Directory> _ensureDirectory() async {
    final directory = _directory ??
        Directory(p.join(
          (await getApplicationDocumentsDirectory()).path,
          'just_read_it',
        ));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }
}
