import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/tts_service.dart';

class ModelSelectorCard extends ConsumerWidget {
  const ModelSelectorCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(ttsConfigProvider);
    return Card(
      child: ListTile(
        title: const Text('Voice Model'),
        subtitle: Text(config.modelPath ?? 'Unassigned'),
        trailing: const Icon(Icons.keyboard_voice),
        onTap: () {
          // TODO: wire to GenUI-suggested model choices.
        },
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
      onChanged: (enabled) {
        // In a real build, this would trigger a theme controller.
      },
    );
  }
}
