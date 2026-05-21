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
  );
}
