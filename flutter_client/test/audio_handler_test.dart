import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_read_it/services/audio_handler.dart';

void main() {
  test('seekToWordTarget seeks to queued chunk index', () async {
    final player = _FakeAudioPlayerController();
    final handler = TtsAudioHandler(player: player);
    final tempDir = await Directory.systemTemp.createTemp('jri_audio_seek_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final first = File('${tempDir.path}/first.wav')..writeAsBytesSync([0]);
    final second = File('${tempDir.path}/second.wav')..writeAsBytesSync([0]);

    await handler.playFileQueue(
      first,
      duration: const Duration(seconds: 1),
      totalDuration: const Duration(seconds: 2),
    );
    await handler.appendFileToQueue(second);
    player.seekCalls.clear();

    await handler.seekToWordTarget(
      const Duration(milliseconds: 750),
      chunkIndex: 1,
    );

    expect(player.seekCalls, hasLength(1));
    expect(player.seekCalls.single.position, const Duration(milliseconds: 750));
    expect(player.seekCalls.single.index, 1);
  });

  test('stop rewinds queued playback to the first chunk before stopping',
      () async {
    final player = _FakeAudioPlayerController();
    final handler = TtsAudioHandler(player: player);
    final tempDir = await Directory.systemTemp.createTemp('jri_audio_handler_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final file = File('${tempDir.path}/chunk.wav')..writeAsBytesSync([0]);

    await handler.playFileQueue(
      file,
      duration: const Duration(seconds: 1),
      totalDuration: const Duration(seconds: 3),
    );
    player.currentIndexValue = 1;
    player.stopCalls = 0;

    await handler.stop();

    expect(player.seekCalls, hasLength(1));
    expect(player.seekCalls.single.position, Duration.zero);
    expect(player.seekCalls.single.index, 0);
    expect(player.pauseCalls, 1);
    expect(player.stopCalls, 1);
  });
}

class _FakeAudioPlayerController implements AudioPlayerController {
  final seekCalls = <_SeekCall>[];

  var pauseCalls = 0;
  var stopCalls = 0;
  var playingValue = false;
  var positionValue = Duration.zero;
  var currentIndexValue = 0;
  var speedValue = 1.0;
  var processingStateValue = ProcessingState.ready;

  @override
  Stream<PlaybackEvent> get playbackEventStream =>
      const Stream<PlaybackEvent>.empty();

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<int?> get currentIndexStream => const Stream<int?>.empty();

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Duration get position => positionValue;

  @override
  Duration get bufferedPosition => positionValue;

  @override
  int? get currentIndex => currentIndexValue;

  @override
  bool get playing => playingValue;

  @override
  double get speed => speedValue;

  @override
  ProcessingState get processingState => processingStateValue;

  @override
  Future<void> play() async {
    playingValue = true;
    positionValue = const Duration(seconds: 1);
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    playingValue = false;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    processingStateValue = ProcessingState.idle;
  }

  @override
  Future<void> setSpeed(double speed) async {
    speedValue = speed;
  }

  @override
  Future<void> setAudioSource(AudioSource source) async {}

  @override
  Future<void> seek(Duration position, {int? index}) async {
    seekCalls.add(_SeekCall(position, index));
    positionValue = position;
    if (index != null) {
      currentIndexValue = index;
    }
  }
}

class _SeekCall {
  const _SeekCall(this.position, this.index);

  final Duration position;
  final int? index;
}
