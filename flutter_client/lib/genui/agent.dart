import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/tts_service.dart';
import '../services/audio_handler.dart';

final genUiAgentProvider = Provider<GenUiAgent>((ref) {
  return GenUiAgent(ref);
});

class GenUiAgent {
  GenUiAgent(this._ref);

  final Ref _ref;

  Future<void> applyPrompt(String prompt) async {
    // TODO: connect to Gemini / GenUI orchestration service.
    final config = _ref.read(ttsConfigProvider.notifier);
    config.updateFromPrompt(prompt);
  }
}
