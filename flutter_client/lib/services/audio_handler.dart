import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

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
    _eventSub = _player.playbackEventStream.listen(_broadcastState);
  }

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlaybackEvent>? _eventSub;
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
    );
    return duration;
  }

  Future<void> _playSource(
    AudioSource source, {
    required String id,
    required Duration duration,
    required double speed,
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
  }

  Stream<Duration> positionStream() => _player.positionStream;

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await _eventSub?.cancel();
    await super.stop();
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
