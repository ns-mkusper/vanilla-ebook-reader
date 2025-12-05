import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/llm_models.dart';
import '../services/model_repository.dart';
import '../services/tts_service.dart';

class ModelSelectorCard extends ConsumerWidget {
  const ModelSelectorCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(ttsConfigProvider);
    return Card(
      child: ListTile(
        title: const Text('Voice Model'),
        subtitle: Text(config.voice.displayName),
        trailing: const Icon(Icons.keyboard_voice_outlined),
        onTap: () => _openVoiceSheet(context, ref),
      ),
    );
  }

  Future<void> _openVoiceSheet(BuildContext context, WidgetRef ref) async {
    final preset = await showModalBottomSheet<VoiceModelPreset>(
      context: context,
      builder: (context) => const _VoicePresetSheet(),
    );
    if (preset == null || !context.mounted) {
      return;
    }
    final repo = ref.read(modelRepositoryProvider);
    final notifier = ref.read(ttsConfigProvider.notifier);
    Future<VoiceSelection> resolve() async {
      if (preset.backend == TtsEngineBackend.piper) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Dialog(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Preparing Piper voice...'),
                ],
              ),
            ),
          ),
        );
        try {
          final selection = await repo.ensurePresetReady(preset);
          if (context.mounted) {
            Navigator.of(context, rootNavigator: true).pop();
          }
          return selection;
        } catch (err) {
          if (context.mounted) {
            Navigator.of(context, rootNavigator: true).pop();
          }
          rethrow;
        }
      }
      return VoiceSelection(
        id: preset.id,
        displayName: preset.label,
        backend: preset.backend,
        modelPath: preset.id,
      );
    }

    try {
      final selection = await resolve();
      notifier.selectVoice(selection);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Voice set to ${selection.displayName}')),
        );
      }
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Voice install failed: $err')),
        );
      }
    }
  }
}

class _VoicePresetSheet extends ConsumerWidget {
  const _VoicePresetSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(ttsConfigProvider);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          const Text('Select a voice',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final preset in voiceModelPresets)
                  RadioListTile<String>(
                    value: preset.id,
                    groupValue: config.voice.id,
                    onChanged: (_) => Navigator.of(context).pop(preset),
                    title: Text(preset.label),
                    subtitle: Text(preset.description),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LlmModelDropdown extends ConsumerWidget {
  const LlmModelDropdown({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(ttsConfigProvider);
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: 'GenUI LLM Model',
        border: OutlineInputBorder(),
      ),
      initialValue: config.llmModel,
      items: [
        for (final option in llmModelOptions)
          DropdownMenuItem(
            value: option.id,
            child: Text(option.label),
          ),
      ],
      onChanged: (value) {
        if (value != null) {
          ref.read(ttsConfigProvider.notifier).selectLlmModel(value);
        }
      },
    );
  }
}

class SpeedSlider extends ConsumerWidget {
  const SpeedSlider({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(ttsConfigProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Playback Speed'),
        Slider(
          value: config.rate,
          min: 0.5,
          max: 3.0,
          divisions: 25,
          label: config.rate.toStringAsFixed(2),
          onChanged: (value) =>
              ref.read(ttsConfigProvider.notifier).updateRate(value),
        ),
      ],
    );
  }
}

class ThemeToggle extends ConsumerWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SwitchListTile(
      value: isDark,
      title: const Text('Dark Mode'),
      onChanged: (_) {},
    );
  }
}
