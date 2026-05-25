import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_read_it/api.dart' as bridge;

import '../services/model_repository.dart';
import '../services/text_analysis.dart';
import 'audio_handler.dart';
import 'bridge_service.dart';

final ttsConfigProvider =
    StateNotifierProvider<TtsConfigNotifier, TtsConfig>((ref) {
  return TtsConfigNotifier();
});

final currentWordIndexProvider = StateProvider<int>((ref) => 0);
final wordBoundariesProvider =
    StateProvider<List<TextWordBoundary>>((ref) => const []);
final wordCuesProvider = StateProvider<List<WordCue>>((ref) => const []);
final wordChunkOffsetsProvider = StateProvider<List<int>>((ref) => const []);
final wordChunkDurationsProvider =
    StateProvider<List<Duration>>((ref) => const []);
final ttsStatusProvider = StateProvider<String>((ref) => 'Idle');
final ttsStopSignalProvider = StateProvider<int>((ref) => 0);

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
    final stopSignal = _ref.read(ttsStopSignalProvider);
    _ref.read(ttsStatusProvider.notifier).state = 'Preparing audio...';
    unawaited(_ref.read(audioHandlerProvider));

    final repo = _ref.read(modelRepositoryProvider);
    final config = _ref.read(ttsConfigProvider);
    final notifier = _ref.read(ttsConfigProvider.notifier);

    var voice = await repo.ensureSelectionReady(config.voice);
    notifier.hydrateVoice(voice);

    switch (voice.backend) {
      case TtsEngineBackend.androidSystem:
        await _speakWithPlatformTts(text, voice, config, stopSignal);
      case TtsEngineBackend.fliteClassic:
        await _speakWithChunkedRustFlite(text, voice, config, stopSignal);
      case TtsEngineBackend.piper:
        await _speakWithRustEngine(text, voice, config, stopSignal);
    }
  }

  Future<void> _speakWithPlatformTts(
    String text,
    VoiceSelection voice,
    TtsConfig config,
    int stopSignal,
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

    if (voice.backend == TtsEngineBackend.androidSystem) {
      await _configureAndroidVoice(flutterTts, voice);
    }

    final maxInputLength = await _platformMaxInputLength(flutterTts);
    final fullChunks = splitPlatformTtsText(text, maxChars: maxInputLength);
    if (fullChunks.isEmpty) return;

    // Android's file synthesis latency scales with the number of characters in
    // the requested utterance. For long documents, synthesize a tiny first
    // segment and hand it to the native media player immediately instead of
    // making the user wait for a max-sized chunk or the whole document. The
    // remaining full-document timeline is still built from the complete text so
    // visual highlighting proves the imported long document made it to playback.
    final lowLatencyStartup = fullChunks.length > 1;
    final startupChunks = lowLatencyStartup
        ? splitPlatformTtsText(
            text,
            maxChars: _platformStartupChunkMaxChars,
          )
        : fullChunks;
    final chunks = lowLatencyStartup && startupChunks.isNotEmpty
        ? <String>[startupChunks.first]
        : fullChunks;
    final advertisedChunkCount = lowLatencyStartup
        ? (text.length / _platformStartupChunkMaxChars).ceil()
        : fullChunks.length;
    final startupTimer = Stopwatch()..start();

    _ref.read(ttsStatusProvider.notifier).state = lowLatencyStartup
        ? 'Preparing instant playback...'
        : 'Preparing audio chunk 1 of ${chunks.length}...';
    final chunkFiles = <File>[];
    try {
      for (var index = 0; index < chunks.length; index++) {
        _ref.read(ttsStatusProvider.notifier).state = lowLatencyStartup
            ? 'Preparing instant playback...'
            : 'Preparing audio chunk ${index + 1} of ${chunks.length}...';
        final chunkFile = index == 0
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
        if (_ref.read(ttsStopSignalProvider) != stopSignal) {
          _ref.read(ttsStatusProvider.notifier).state = 'Stopped';
          return;
        }
        chunkFiles.add(chunkFile);
        if (lowLatencyStartup && index == 0) {
          await _playInitialPlatformQueueFile(
            generated,
            fullText: text,
            startupChunks: startupChunks,
            firstChunkText: chunks[index],
            config: config,
            status: 'Playing chunk 1 of $advertisedChunkCount',
            stopSignal: stopSignal,
          );
          debugPrint(
            'JRI_TTS_FIRST_AUDIO_READY_MS=${startupTimer.elapsedMilliseconds} '
            'chars=${chunks[index].length} totalChars=${text.length}',
          );
          unawaited(_synthesizeAndAppendPlatformChunks(
            flutterTts,
            startupChunks.skip(1).toList(),
            cacheDir,
            stopSignal: stopSignal,
            audioHandler: await _ref.read(audioHandlerProvider),
            totalChunks: advertisedChunkCount,
          ));
          return;
        }
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

    await _playSynthesizedPlatformFile(
      generated,
      text: text,
      config: config,
      status: 'Playing',
      stopSignal: stopSignal,
    );
  }

  Future<Duration> _playInitialPlatformQueueFile(
    File generated, {
    required String fullText,
    required List<String> startupChunks,
    required String firstChunkText,
    required TtsConfig config,
    required String status,
    required int stopSignal,
  }) async {
    if (_ref.read(ttsStopSignalProvider) != stopSignal) {
      _ref.read(ttsStatusProvider.notifier).state = 'Stopped';
      return Duration.zero;
    }
    _ref.read(ttsStatusProvider.notifier).state = 'Starting media player...';
    final duration = await _wavDuration(generated);
    final totalDuration = _estimateFullDuration(
      totalChars: fullText.length,
      firstChunkChars: firstChunkText.length,
      firstDuration: duration,
    );
    final audioHandler = await _ref.read(audioHandlerProvider);
    await audioHandler.playFileQueue(
      generated,
      duration: duration,
      totalDuration: totalDuration,
      speed: config.rate,
    );
    if (_ref.read(ttsStopSignalProvider) != stopSignal) {
      await audioHandler.stop();
      _ref.read(ttsStatusProvider.notifier).state = 'Stopped';
      return Duration.zero;
    }
    _ref.read(ttsStatusProvider.notifier).state = status;
    _attachChunkedTextTimeline(
      fullText,
      startupChunks,
      totalDuration,
      audioHandler,
    );
    _ref.read(wordChunkDurationsProvider.notifier).state = [duration];
    return duration;
  }

  Future<void> _playSynthesizedPlatformFile(
    File generated, {
    required String text,
    required TtsConfig config,
    required String status,
    required int stopSignal,
  }) async {
    if (_ref.read(ttsStopSignalProvider) != stopSignal) {
      _ref.read(ttsStatusProvider.notifier).state = 'Stopped';
      return;
    }
    _ref.read(ttsStatusProvider.notifier).state = 'Starting media player...';
    final duration = await _wavDuration(generated);
    final audioHandler = await _ref.read(audioHandlerProvider);
    await audioHandler.playFile(
      generated,
      duration: duration,
      speed: config.rate,
    );
    if (_ref.read(ttsStopSignalProvider) != stopSignal) {
      await audioHandler.stop();
      _ref.read(ttsStatusProvider.notifier).state = 'Stopped';
      return;
    }
    _ref.read(ttsStatusProvider.notifier).state = status;
    _attachTextTimeline(text, duration, audioHandler);
  }

  Future<void> _synthesizeAndAppendPlatformChunks(
    FlutterTts flutterTts,
    List<String> chunks,
    Directory cacheDir, {
    required int stopSignal,
    required TtsAudioHandler audioHandler,
    required int totalChunks,
  }) async {
    for (var index = 0; index < chunks.length; index++) {
      if (_ref.read(ttsStopSignalProvider) != stopSignal) return;
      final chunkNumber = index + 2;
      _ref.read(ttsStatusProvider.notifier).state =
          'Preparing audio chunk $chunkNumber of $totalChunks...';
      final chunkFile = File(
        '${cacheDir.path}/just_read_it_tts_queue_${DateTime.now().microsecondsSinceEpoch}_$index.wav',
      );
      await flutterTts.synthesizeToFile(chunks[index], chunkFile.path, true);
      if (_ref.read(ttsStopSignalProvider) != stopSignal) {
        if (await chunkFile.exists()) await chunkFile.delete();
        return;
      }
      if (!await chunkFile.exists() || await chunkFile.length() <= 44) {
        debugPrint('Skipping empty synthesized queue chunk $chunkNumber.');
        continue;
      }
      final chunkDuration = await _wavDuration(chunkFile);
      final durations = List<Duration>.from(
        _ref.read(wordChunkDurationsProvider),
      )..add(chunkDuration);
      _ref.read(wordChunkDurationsProvider.notifier).state = durations;
      await audioHandler.appendFileToQueue(chunkFile);
      debugPrint(
        'JRI_TTS_BUFFERED_CHUNK=$chunkNumber/$totalChunks '
        'durationMs=${chunkDuration.inMilliseconds}',
      );
      if (_ref.read(ttsStatusProvider) != 'Paused') {
        _ref.read(ttsStatusProvider.notifier).state =
            'Playing chunk $chunkNumber of $totalChunks';
      }
    }
  }

  Duration _estimateFullDuration({
    required int totalChars,
    required int firstChunkChars,
    required Duration firstDuration,
  }) {
    if (firstChunkChars <= 0 || firstDuration <= Duration.zero) {
      return const Duration(seconds: 1);
    }
    final estimatedMs =
        firstDuration.inMilliseconds * totalChars / firstChunkChars;
    return Duration(milliseconds: estimatedMs.round().clamp(1000, 86400000));
  }

  Future<void> _speakWithChunkedRustFlite(
    String text,
    VoiceSelection voice,
    TtsConfig config,
    int stopSignal,
  ) async {
    await initializeTtsBridge();
    final chunks = splitPlatformTtsText(
      text,
      maxChars: _platformStartupChunkMaxChars,
    );
    if (chunks.isEmpty) return;

    final startupTimer = Stopwatch()..start();
    _ref.read(ttsStatusProvider.notifier).state =
        'Preparing instant playback...';
    final cacheDir = await getTemporaryDirectory();
    final firstChunk = await _synthesizeRustPcm(
      chunks.first,
      const bridge.EngineBackend.flite(),
      voice,
    );
    final firstFile = await _writePcmWav(
      firstChunk.pcmBytes,
      firstChunk.sampleRate,
      File(
          '${cacheDir.path}/just_read_it_flite_start_${DateTime.now().microsecondsSinceEpoch}.wav'),
    );
    final firstDuration = await _wavDuration(firstFile);
    final totalDuration = _estimateFullDuration(
      totalChars: text.length,
      firstChunkChars: chunks.first.length,
      firstDuration: firstDuration,
    );
    final audioHandler = await _ref.read(audioHandlerProvider);
    await audioHandler.playFileQueue(
      firstFile,
      duration: firstDuration,
      totalDuration: totalDuration,
      speed: config.rate,
    );
    if (_ref.read(ttsStopSignalProvider) != stopSignal) {
      await audioHandler.stop();
      _ref.read(ttsStatusProvider.notifier).state = 'Stopped';
      return;
    }
    _ref.read(ttsStatusProvider.notifier).state =
        'Playing chunk 1 of ${chunks.length}';
    _attachChunkedTextTimeline(text, chunks, totalDuration, audioHandler);
    _ref.read(wordChunkDurationsProvider.notifier).state = [firstDuration];
    debugPrint(
      'JRI_TTS_FIRST_AUDIO_READY_MS=${startupTimer.elapsedMilliseconds} '
      'chars=${chunks.first.length} totalChars=${text.length}',
    );
    unawaited(_synthesizeAndAppendRustChunks(
      chunks.skip(1).toList(),
      cacheDir,
      stopSignal: stopSignal,
      audioHandler: audioHandler,
      voice: voice,
      totalChunks: chunks.length,
    ));
  }

  Future<void> _speakWithRustEngine(
    String text,
    VoiceSelection voice,
    TtsConfig config,
    int stopSignal,
  ) async {
    await initializeTtsBridge();
    final backend = switch (voice.backend) {
      TtsEngineBackend.fliteClassic => const bridge.EngineBackend.flite(),
      TtsEngineBackend.piper => bridge.EngineBackend.piper(
          bridge.PiperBackendConfig(
            modelPath: voice.modelPath!,
            configPath: voice.configPath,
            speaker: null,
            sampleRate: null,
          ),
        ),
      TtsEngineBackend.androidSystem =>
        throw StateError('Android system TTS should not use Rust engine'),
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

    if (_ref.read(ttsStopSignalProvider) != stopSignal) {
      _ref.read(ttsStatusProvider.notifier).state = 'Stopped';
      return;
    }
    _ref.read(ttsStatusProvider.notifier).state = 'Starting media player...';
    final audioHandler = await _ref.read(audioHandlerProvider);
    final duration = await audioHandler.playPcm(
      pcmBytes,
      resolvedRate,
      speed: config.rate,
    );
    if (_ref.read(ttsStopSignalProvider) != stopSignal) {
      await audioHandler.stop();
      _ref.read(ttsStatusProvider.notifier).state = 'Stopped';
      return;
    }
    _ref.read(ttsStatusProvider.notifier).state = 'Playing';
    _attachTextTimeline(text, duration, audioHandler);
  }

  Future<_RustPcmAudio> _synthesizeRustPcm(
    String text,
    bridge.EngineBackend backend,
    VoiceSelection voice,
  ) async {
    final request = bridge.EngineRequest(backend: backend, gainDb: null);
    final buffer = BytesBuilder();
    int? sampleRate;
    var totalSamples = 0;
    await for (final chunk
        in bridge.streamAudio(text: text, request: request)) {
      final pcmView = chunk.pcm.buffer.asUint8List(
        chunk.pcm.offsetInBytes,
        chunk.pcm.lengthInBytes,
      );
      buffer.add(pcmView);
      sampleRate ??= chunk.sampleRate;
      totalSamples += chunk.pcm.length;
    }
    if (totalSamples == 0) {
      throw StateError('Engine ${voice.id} produced no audio.');
    }
    return _RustPcmAudio(buffer.takeBytes(), sampleRate ?? _fallbackSampleRate);
  }

  Future<File> _writePcmWav(
      Uint8List pcmBytes, int sampleRate, File output) async {
    final bytes = BytesBuilder(copy: false)
      ..add(_wavHeader(
        dataLength: pcmBytes.length,
        sampleRate: sampleRate,
        channels: 1,
        bitsPerSample: 16,
      ))
      ..add(pcmBytes);
    await output.writeAsBytes(bytes.takeBytes(), flush: true);
    return output;
  }

  Future<void> _synthesizeAndAppendRustChunks(
    List<String> chunks,
    Directory cacheDir, {
    required int stopSignal,
    required TtsAudioHandler audioHandler,
    required VoiceSelection voice,
    required int totalChunks,
  }) async {
    for (var index = 0; index < chunks.length; index++) {
      if (_ref.read(ttsStopSignalProvider) != stopSignal) return;
      final chunkNumber = index + 2;
      _ref.read(ttsStatusProvider.notifier).state =
          'Preparing audio chunk $chunkNumber of $totalChunks...';
      final audio = await _synthesizeRustPcm(
        chunks[index],
        const bridge.EngineBackend.flite(),
        voice,
      );
      final file = await _writePcmWav(
        audio.pcmBytes,
        audio.sampleRate,
        File(
            '${cacheDir.path}/just_read_it_flite_queue_${DateTime.now().microsecondsSinceEpoch}_$index.wav'),
      );
      if (_ref.read(ttsStopSignalProvider) != stopSignal) {
        if (await file.exists()) await file.delete();
        return;
      }
      final duration = await _wavDuration(file);
      final durations =
          List<Duration>.from(_ref.read(wordChunkDurationsProvider))
            ..add(duration);
      _ref.read(wordChunkDurationsProvider.notifier).state = durations;
      await audioHandler.appendFileToQueue(file);
      debugPrint(
        'JRI_TTS_BUFFERED_CHUNK=$chunkNumber/$totalChunks '
        'durationMs=${duration.inMilliseconds}',
      );
    }
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
    _ref.read(wordChunkOffsetsProvider.notifier).state = const [0];
    _ref.read(wordChunkDurationsProvider.notifier).state = [duration];
    final cues = buildWordCues(boundaries.length, duration);
    _ref.read(wordCuesProvider.notifier).state = cues;
    _ref.read(currentWordIndexProvider.notifier).state = 0;
    _attachTimeline(audioHandler, cues);
  }

  void _attachChunkedTextTimeline(
    String text,
    List<String> chunks,
    Duration totalDuration,
    TtsAudioHandler audioHandler,
  ) {
    final boundaries = computeWordBoundaries(text);
    _ref.read(wordBoundariesProvider.notifier).state = boundaries;
    final chunkWordCounts = chunks
        .map((chunk) => computeWordBoundaries(chunk).length)
        .where((count) => count > 0)
        .toList(growable: false);
    final offsets = <int>[];
    var cursor = 0;
    for (final count in chunkWordCounts) {
      offsets.add(cursor);
      cursor += count;
    }
    _ref.read(wordChunkOffsetsProvider.notifier).state =
        offsets.isEmpty ? const [0] : offsets;
    _ref.read(wordChunkDurationsProvider.notifier).state = const [];
    final cues = buildWordCues(boundaries.length, totalDuration);
    _ref.read(wordCuesProvider.notifier).state = cues;
    _ref.read(currentWordIndexProvider.notifier).state = 0;
    _attachChunkedTimeline(
      audioHandler,
      boundaries,
      chunkWordCounts,
      totalDuration,
    );
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

  void _attachChunkedTimeline(
    TtsAudioHandler handler,
    List<TextWordBoundary> boundaries,
    List<int> chunkWordCounts,
    Duration fallbackTotalDuration,
  ) {
    _positionSub?.cancel();
    if (boundaries.isEmpty || chunkWordCounts.isEmpty) {
      return;
    }
    _positionSub = handler.positionStream().listen((position) {
      final currentIndex = (handler.currentIndex ?? 0)
          .clamp(0, chunkWordCounts.length - 1)
          .toInt();
      final chunkStartWord = _ref.read(wordChunkOffsetsProvider)[currentIndex];
      final chunkWordCount = chunkWordCounts[currentIndex];
      final nextChunkStart = currentIndex + 1 < chunkWordCounts.length
          ? _ref.read(wordChunkOffsetsProvider)[currentIndex + 1]
          : boundaries.length;
      final effectiveChunkWords = min(
        chunkWordCount,
        max(1, nextChunkStart - chunkStartWord),
      );
      final durations = _ref.read(wordChunkDurationsProvider);
      final chunkDuration = currentIndex < durations.length
          ? durations[currentIndex]
          : _estimateChunkDuration(
              currentIndex: currentIndex,
              chunkWordCounts: chunkWordCounts,
              fallbackTotalDuration: fallbackTotalDuration,
            );
      final cues = buildWordCues(effectiveChunkWords, chunkDuration);
      final localIndex = wordIndexForPosition(position, cues);
      _ref.read(currentWordIndexProvider.notifier).state =
          min(chunkStartWord + localIndex, boundaries.length - 1);
    });
  }

  Duration _estimateChunkDuration({
    required int currentIndex,
    required List<int> chunkWordCounts,
    required Duration fallbackTotalDuration,
  }) {
    final totalWords =
        chunkWordCounts.fold<int>(0, (sum, count) => sum + count);
    if (totalWords <= 0 || fallbackTotalDuration <= Duration.zero) {
      return const Duration(seconds: 15);
    }
    final estimatedMs = fallbackTotalDuration.inMilliseconds *
        chunkWordCounts[currentIndex] /
        totalWords;
    return Duration(milliseconds: estimatedMs.round().clamp(1000, 600000));
  }
}

Future<void> _configureAndroidVoice(
  FlutterTts flutterTts,
  VoiceSelection voice,
) async {
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
    final result = await flutterTts.setVoice(selectedVoice);
    if (result != 1) {
      return false;
    }
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

class _RustPcmAudio {
  const _RustPcmAudio(this.pcmBytes, this.sampleRate);

  final Uint8List pcmBytes;
  final int sampleRate;
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
const _platformStartupChunkMaxChars = 360;
const _chunkSeparator = '\n\n';
