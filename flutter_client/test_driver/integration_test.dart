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
      final base64Wav = data?['playbackWavBase64'];
      if (base64Wav is! String || base64Wav.isEmpty) {
        throw StateError('Missing playbackWavBase64 from integration test.');
      }
      final wav = File('${directory.path}/voice_sample_from_emulator.wav');
      await wav.writeAsBytes(base64Decode(base64Wav), flush: true);
      final response = File('${directory.path}/integration_response_data.json');
      final sanitized =
          Map<String, dynamic>.from(data ?? const <String, dynamic>{})
            ..remove('playbackWavBase64');
      await response.writeAsString(
        const JsonEncoder.withIndent('  ').convert(sanitized),
        flush: true,
      );
    },
  );
}
