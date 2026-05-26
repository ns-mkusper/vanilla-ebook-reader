import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        subtitle: Text(
          config.voice.displayName,
          key: const Key('voice.current'),
        ),
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
    final notifier = ref.read(ttsConfigProvider.notifier);
    final selection = VoiceSelection(
      id: preset.id,
      displayName: preset.label,
      backend: preset.backend,
      modelPath: preset.backend == TtsEngineBackend.piper ? null : preset.id,
      androidEngine: preset.androidEngine,
      androidVoiceName: preset.androidVoiceName,
      androidVoiceLocale: preset.androidVoiceLocale,
    );
    notifier.selectVoice(selection);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voice set to ${selection.displayName}')),
      );
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
          const Text(
            'Select a voice',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final preset in voiceModelPresets)
                  RadioListTile<String>(
                    key: Key('voice.preset.${preset.id}'),
                    value: preset.id,
                    // ignore: deprecated_member_use
                    groupValue: config.voice.id,
                    // ignore: deprecated_member_use
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
          key: const Key('playback.speed'),
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

class PitchSlider extends ConsumerWidget {
  const PitchSlider({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(ttsConfigProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Voice Pitch'),
        Slider(
          key: const Key('voice.pitch'),
          value: config.pitch,
          min: 0.7,
          max: 1.4,
          divisions: 14,
          label: config.pitch.toStringAsFixed(2),
          onChanged: (value) =>
              ref.read(ttsConfigProvider.notifier).updatePitch(value),
        ),
      ],
    );
  }
}
