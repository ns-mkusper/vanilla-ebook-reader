import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (
      String screenshotName,
      List<int> screenshotBytes, [
      Map<String, Object?>? args,
    ]) async {
      final directory = Directory('build/screenshots');
      await directory.create(recursive: true);
      final image = File('${directory.path}/$screenshotName.png');
      await image.writeAsBytes(screenshotBytes, flush: true);
      return true;
    },
    responseDataCallback: (data) async {
      final directory = Directory('build/screenshots');
      await directory.create(recursive: true);
      final response = File('${directory.path}/integration_response_data.json');
      final sanitized =
          Map<String, dynamic>.from(data ?? const <String, dynamic>{})
            ..remove('playbackWavBase64');
      await response.writeAsString(
        const JsonEncoder.withIndent('  ').convert(sanitized),
        flush: true,
      );

      final base64Wav = data?['playbackWavBase64'];
      if (base64Wav == null) {
        return;
      }
      if (base64Wav is! String || base64Wav.isEmpty) {
        throw StateError('Invalid playbackWavBase64 from integration test.');
      }
      final rawName = data?['playbackWavName'];
      final wavName = rawName is String && rawName.isNotEmpty
          ? rawName
          : 'voice_sample_from_emulator.wav';
      if (wavName.contains('/') || wavName.contains('\\')) {
        throw ArgumentError.value(
            wavName, 'playbackWavName', 'must be a file name');
      }
      final wav = File('${directory.path}/$wavName');
      await wav.writeAsBytes(base64Decode(base64Wav), flush: true);
    },
  );
}
