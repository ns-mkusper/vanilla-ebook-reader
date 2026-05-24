import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

final audioHandlerProvider = Provider<Future<TtsAudioHandler>>((ref) async {
  return AudioService.init(
    builder: () => TtsAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'just.read.it.channel',
      androidNotificationChannelName: 'Just Read It',
      androidNotificationOngoing: true,
    ),
  );
});

class TtsAudioHandler extends BaseAudioHandler with SeekHandler {
  TtsAudioHandler() {
    _player.playbackEventStream.listen(_broadcastState);
  }

  final AudioPlayer _player = AudioPlayer();
  MediaItem? _currentItem;

  Future<Duration> playPcm(
    Uint8List pcmBytes,
    int sampleRate, {
    double speed = 1.0,
  }) async {
    if (pcmBytes.isEmpty || sampleRate <= 0) {
      return Duration.zero;
    }

    final wavBytes = _buildWavBytes(pcmBytes, sampleRate);
    final source = _MemoryAudioSource(wavBytes);
    final duration = Duration(
      milliseconds: (pcmBytes.length / 2 / sampleRate * 1000).round(),
    );
    await _playSource(
      source,
      id: 'memory://just-read-it/tts-${DateTime.now().microsecondsSinceEpoch}.wav',
      duration: duration,
      speed: speed,
      playbackExportBytes: wavBytes,
    );
    return duration;
  }

  Future<Duration> playFile(
    File file, {
    required Duration duration,
    double speed = 1.0,
  }) async {
    await _playSource(
      AudioSource.uri(file.uri),
      id: file.uri.toString(),
      duration: duration,
      speed: speed,
      playbackExportFile: file,
    );
    return duration;
  }

  Future<void> _playSource(
    AudioSource source, {
    required String id,
    required Duration duration,
    required double speed,
    Uint8List? playbackExportBytes,
    File? playbackExportFile,
  }) async {
    _currentItem = MediaItem(
      id: id,
      album: 'Just Read It',
      title: 'Read-Aloud Playback',
      duration: duration,
    );
    mediaItem.add(_currentItem);

    await _player.stop();
    await _player.setSpeed(speed.clamp(0.5, 3.0));
    await _player.setAudioSource(source);
    unawaited(_player.play());
    await _waitForNativePlaybackStarted(duration);
    await _exportPlaybackAudioIfRequested(
      sourceFile: playbackExportFile,
      sourceBytes: playbackExportBytes,
    );
  }

  Future<void> _waitForNativePlaybackStarted(Duration duration) async {
    final requiredProgress = duration < const Duration(seconds: 1)
        ? const Duration(milliseconds: 100)
        : const Duration(milliseconds: 500);
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      if (_player.playing && _player.position >= requiredProgress) {
        debugPrint(
          'JRI_PLAYBACK_STARTED position=${_player.position.inMilliseconds}ms '
          'speed=${_player.speed}',
        );
        return;
      }
      if (_player.processingState == ProcessingState.completed &&
          _player.position > Duration.zero) {
        debugPrint(
          'JRI_PLAYBACK_COMPLETED position=${_player.position.inMilliseconds}ms '
          'speed=${_player.speed}',
        );
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError(
      'Native playback did not advance beyond '
      '${requiredProgress.inMilliseconds}ms.',
    );
  }

  Future<void> _exportPlaybackAudioIfRequested({
    File? sourceFile,
    Uint8List? sourceBytes,
  }) async {
    const shouldExport = bool.fromEnvironment('JRI_EXPORT_TTS_WAV');
    if (!shouldExport) return;
    final cacheDir = await getTemporaryDirectory();
    final file = File('${cacheDir.path}/just_read_it_playback_sample.wav');
    if (sourceFile != null) {
      await sourceFile.copy(file.path);
    } else if (sourceBytes != null) {
      await file.writeAsBytes(sourceBytes, flush: true);
    } else {
      throw StateError('No playback audio source available to export.');
    }
    debugPrint('JRI_PLAYBACK_WAV_PATH=${file.path}');
    debugPrint('JRI_PLAYBACK_WAV_READY');
  }

  Stream<Duration> positionStream() => _player.positionStream;
  Stream<bool> playingStream() => _player.playingStream;
  bool get isPlaying => _player.playing;

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> play() async {
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.pause();
    await _player.seek(Duration.zero);
    await _player.stop();
    debugPrint('JRI_PLAYBACK_STOPPED');
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      processingState: AudioProcessingState.idle,
      updatePosition: Duration.zero,
    ));
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> fastForward() =>
      _player.seek(_player.position + const Duration(seconds: 15));

  @override
  Future<void> rewind() =>
      _player.seek(_player.position - const Duration(seconds: 15));

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    final processingState = _mapProcessingState(_player.processingState);
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.rewind,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.fastForward,
        ],
        androidCompactActionIndices: const [0, 1, 3],
        playing: playing,
        processingState: processingState,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ),
    );
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  Uint8List _buildWavBytes(Uint8List pcmBytes, int sampleRate) {
    final header = _buildWavHeader(
      dataLength: pcmBytes.length,
      sampleRate: sampleRate,
      bytesPerSample: 2,
      channels: 1,
    );
    final bytes = Uint8List(header.length + pcmBytes.length);
    bytes.setRange(0, header.length, header);
    bytes.setRange(header.length, bytes.length, pcmBytes);
    return bytes;
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
}

// ignore: experimental_member_use
class _MemoryAudioSource extends StreamAudioSource {
  _MemoryAudioSource(this.bytes);

  final Uint8List bytes;

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final resolvedStart = start ?? 0;
    final resolvedEnd = end ?? bytes.length;
    final slice = bytes.sublist(resolvedStart, resolvedEnd);
    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: slice.length,
      offset: resolvedStart,
      stream: Stream.value(slice),
      contentType: 'audio/wav',
    );
  }
}
