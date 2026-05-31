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

class PlaybackPreferenceControls extends StatelessWidget {
  const PlaybackPreferenceControls({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: SpeedDropdown()),
        SizedBox(width: 12),
        Expanded(child: PitchDropdown()),
      ],
    );
  }
}

class SpeedDropdown extends ConsumerWidget {
  const SpeedDropdown({super.key});

  static const _options = <double>[
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
    2.5,
    3.0,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(ttsConfigProvider);
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Speed',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<double>(
          key: const Key('playback.speed'),
          value: _nearestOption(config.rate, _options),
          isExpanded: true,
          items: [
            for (final option in _options)
              DropdownMenuItem<double>(
                value: option,
                child: Text(_formatMultiplier(option)),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;
            ref.read(ttsConfigProvider.notifier).updateRate(value);
          },
        ),
      ),
    );
  }
}

class PitchDropdown extends ConsumerWidget {
  const PitchDropdown({super.key});

  static const _options = <double>[
    0.7,
    0.8,
    0.9,
    1.0,
    1.1,
    1.2,
    1.3,
    1.4,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(ttsConfigProvider);
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Pitch',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<double>(
          key: const Key('voice.pitch'),
          value: _nearestOption(config.pitch, _options),
          isExpanded: true,
          items: [
            for (final option in _options)
              DropdownMenuItem<double>(
                value: option,
                child: Text(_formatMultiplier(option)),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;
            ref.read(ttsConfigProvider.notifier).updatePitch(value);
          },
        ),
      ),
    );
  }
}

double _nearestOption(double value, List<double> options) {
  return options.reduce((closest, option) {
    final closestDistance = (closest - value).abs();
    final optionDistance = (option - value).abs();
    return optionDistance < closestDistance ? option : closest;
  });
}

String _formatMultiplier(double value) {
  return '${value.toStringAsFixed(2)}×';
}
