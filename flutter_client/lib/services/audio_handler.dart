import 'dart:async';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

final audioHandlerProvider = Provider<Future<TtsAudioHandler>>((ref) async {
  return AudioService.init(
    builder: () => TtsAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'tts.beast.channel',
      androidNotificationChannelName: 'TTS Beast',
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

  Future<void> playPcm(Uint8List pcmBytes, int sampleRate) async {
    if (pcmBytes.isEmpty || sampleRate <= 0) {
      return;
    }

    final wavBytes = _buildWavBytes(pcmBytes, sampleRate);
    final uri = Uri.dataFromBytes(wavBytes, mimeType: 'audio/wav');
    _currentItem = MediaItem(
      id: uri.toString(),
      album: 'Generated Speech',
      title: 'TTS Playback',
      duration: Duration(
        milliseconds: (pcmBytes.length / 2 / sampleRate * 1000).round(),
      ),
    );
    mediaItem.add(_currentItem);

    await _player.stop();
    await _player.setAudioSource(AudioSource.uri(uri));
    await _player.play();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
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

  @override
  Future<void> close() async {
    await _eventSub?.cancel();
    await _player.dispose();
    await super.close();
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    final processingState = _mapProcessingState(_player.processingState);
    playbackState.add(
      PlaybackState(
        controls: [
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
        ],
        androidCompactActionIndices: const [0, 1],
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
        return AudioProcessingState.connecting;
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
