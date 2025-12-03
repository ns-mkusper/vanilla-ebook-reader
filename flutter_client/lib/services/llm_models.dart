class LlmModelOption {
  const LlmModelOption({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;
}

const defaultLlmModel = 'models/gemini-2.0-flash';

const llmModelOptions = <LlmModelOption>[
  LlmModelOption(
    id: 'models/gemini-2.0-flash',
    label: 'Gemini 2.0 Flash',
    description: 'Fast multimodal model tuned for chat + UI orchestration.',
  ),
  LlmModelOption(
    id: 'models/gemini-1.5-pro-exp-0827',
    label: 'Gemini 1.5 Pro Experimental',
    description: 'Higher quality, slightly slower responses.',
  ),
  LlmModelOption(
    id: 'models/gemini-1.5-flash',
    label: 'Gemini 1.5 Flash',
    description: 'Low-latency summarizer for quick prompt cleanup.',
  ),
];
