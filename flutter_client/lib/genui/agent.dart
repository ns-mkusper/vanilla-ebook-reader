import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genui/genui.dart';
import 'package:genui_google_generative_ai/genui_google_generative_ai.dart';
import 'package:json_schema_builder/json_schema_builder.dart' as dsb;

import '../services/llm_models.dart';
import '../services/model_repository.dart';
import '../services/tts_service.dart';

final genUiAgentProvider = Provider<GenUiAgent>((ref) {
  final modelName = ref.watch(ttsConfigProvider.select((cfg) => cfg.llmModel));
  final agent = GenUiAgent(ref, modelName);
  ref.onDispose(agent.dispose);
  return agent;
});

class GenUiAgent {
  GenUiAgent(this._ref, this._modelName)
      : _catalog = CoreCatalogItems.asCatalog(),
        _apiKey = const String.fromEnvironment('GENAI_API_KEY') {
    _manager = GenUiManager(catalog: _catalog);
    _conversation = GenUiConversation(
      genUiManager: _manager,
      contentGenerator: _buildGenerator(),
      onError: (error) => debugPrint('GenUI error: ${error.error}'),
    );
  }

  final Ref _ref;
  final String _modelName;
  final Catalog _catalog;
  late final GenUiManager _manager;
  final String _apiKey;
  late final GenUiConversation _conversation;

  bool get isOnline => _apiKey.isNotEmpty;
  GenUiHost get host => _conversation.host;
  ValueListenable<List<ChatMessage>> get conversation =>
      _conversation.conversation;
  ValueListenable<bool> get isProcessing => _conversation.isProcessing;

  ContentGenerator _buildGenerator() {
    if (_apiKey.isEmpty) {
      return LocalEchoContentGenerator();
    }
    return GoogleGenerativeAiContentGenerator(
      catalog: _catalog,
      apiKey: _apiKey,
      modelName: _modelName,
      systemInstruction: _buildSystemPrompt(),
      additionalTools: [_configTool()],
    );
  }

  AiTool<Map<String, Object?>> _configTool() {
    return DynamicAiTool<Map<String, Object?>>(
      name: 'updateTtsPreferences',
      description:
          'Call this to update the narrator voice, playback speed, and GenUI model.',
      parameters: dsb.S.object(
        properties: {
          'voice_id': dsb.S
              .string(enumValues: voiceModelPresets.map((v) => v.id).toList()),
          'playback_rate': dsb.S.number(minimum: 0.5, maximum: 3.0),
          'llm_model': dsb.S
              .string(enumValues: llmModelOptions.map((o) => o.id).toList()),
        },
      ),
      invokeFunction: _handleConfigUpdate,
    );
  }

  Future<Map<String, Object?>> _handleConfigUpdate(
      Map<String, Object?> args) async {
    final notifier = _ref.read(ttsConfigProvider.notifier);
    if (args['voice_id'] is String) {
      final id = args['voice_id'] as String;
      final preset = voiceModelPresets.firstWhere((p) => p.id == id,
          orElse: () => voiceModelPresets.first);
      final selection =
          await _ref.read(modelRepositoryProvider).ensurePresetReady(preset);
      notifier.selectVoice(selection);
    }
    if (args['playback_rate'] is num) {
      final rate = (args['playback_rate'] as num).toDouble().clamp(0.5, 3.0);
      notifier.updateRate(rate);
    }
    if (args['llm_model'] is String) {
      notifier.selectLlmModel(args['llm_model'] as String);
    }
    return {'status': 'ok'};
  }

  Future<void> applyPrompt(String prompt) async {
    final message = UserMessage.text(prompt);
    await _conversation.sendRequest(message);
    _ref.read(ttsConfigProvider.notifier).updateFromPrompt(prompt);
  }

  void dispose() {
    _conversation.dispose();
  }
}

class LocalEchoContentGenerator implements ContentGenerator {
  LocalEchoContentGenerator();

  final _a2uiController = StreamController<A2uiMessage>.broadcast();
  final _textController = StreamController<String>.broadcast();
  final _errorController = StreamController<ContentGeneratorError>.broadcast();
  final ValueNotifier<bool> _processing = ValueNotifier(false);

  @override
  Stream<A2uiMessage> get a2uiMessageStream => _a2uiController.stream;

  @override
  Stream<String> get textResponseStream => _textController.stream;

  @override
  Stream<ContentGeneratorError> get errorStream => _errorController.stream;

  @override
  ValueListenable<bool> get isProcessing => _processing;

  @override
  Future<void> sendRequest(ChatMessage message,
      {Iterable<ChatMessage>? history}) async {
    _processing.value = true;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _textController.add(
      'GenUI SDK requires a GENAI_API_KEY. Set --dart-define=GENAI_API_KEY=<your key> to enable live suggestions.',
    );
    _processing.value = false;
  }

  @override
  void dispose() {
    _a2uiController.close();
    _textController.close();
    _errorController.close();
    _processing.dispose();
  }
}

String _buildSystemPrompt() {
  final voices = voiceModelPresets.map((v) => v.id).join(', ');
  final llms = llmModelOptions.map((m) => m.id).join(', ');
  return '''You help configure a text-to-speech workstation called TTS Beast.
Available voices: $voices.
Available GenUI LLM models: $llms.
Always call the TTS configuration tools to set voice, playback rate, and LLM when the user describes a new vibe.''';
}
