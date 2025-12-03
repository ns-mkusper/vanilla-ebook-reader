import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genui/genui.dart';

import 'agent.dart';

class GenUiPanel extends ConsumerStatefulWidget {
  const GenUiPanel({super.key});

  @override
  ConsumerState<GenUiPanel> createState() => _GenUiPanelState();
}

class _GenUiPanelState extends ConsumerState<GenUiPanel> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agent = ref.watch(genUiAgentProvider);
    return SafeArea(
      child: Column(
        children: [
          if (!agent.isOnline)
            const ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('GenUI is in offline mode'),
              subtitle: Text(
                  'Set --dart-define=GENAI_API_KEY=your-key to enable live Gemini surfaces.'),
            ),
          Expanded(
            child: ValueListenableBuilder<List<ChatMessage>>(
              valueListenable: agent.conversation,
              builder: (context, messages, _) {
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return _MessageBubble(message: message, agent: agent);
                  },
                );
              },
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: agent.isProcessing,
            builder: (context, isProcessing, _) {
              if (!isProcessing) return const SizedBox.shrink();
              return const LinearProgressIndicator(minHeight: 2);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Describe the vibe you want...',
                    ),
                    onSubmitted: (_) => _sendPrompt(agent),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _sendPrompt(agent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendPrompt(GenUiAgent agent) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await agent.applyPrompt(text);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (mounted) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.agent});

  final ChatMessage message;
  final GenUiAgent agent;

  @override
  Widget build(BuildContext context) {
    return switch (message) {
      UserMessage(:final text) => Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(text,
                style:
                    TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
          ),
        ),
      UserUiInteractionMessage(:final text) => Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(text,
                style:
                    TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
          ),
        ),
      AiTextMessage(:final text) => Align(
          alignment: Alignment.centerLeft,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(text),
            ),
          ),
        ),
      AiUiMessage(:final surfaceId) => Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: GenUiSurface(host: agent.host, surfaceId: surfaceId),
          ),
        ),
      InternalMessage(:final text) => Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        ),
      _ => const SizedBox.shrink(),
    };
  }
}
