import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/assistant_controller.dart';
import '../domain/assistant_entity.dart';

class AssistantPage extends ConsumerStatefulWidget {
  const AssistantPage({super.key});

  @override
  ConsumerState<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends ConsumerState<AssistantPage> {
  final TextEditingController _messageController = TextEditingController();
  AssistantMode _mode = AssistantMode.tutor;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assistantControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Assistant')),
      body: Column(
        children: [
          Expanded(
            child: state.when(
              data: (items) => ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    title: Text(item.responseText),
                    subtitle: Text(
                        'Q: ${item.userText}\nmode: ${item.mode.apiValue}'),
                  );
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text(error.toString())),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                DropdownButton<AssistantMode>(
                  value: _mode,
                  items: const [
                    DropdownMenuItem(
                      value: AssistantMode.tutor,
                      child: Text('Tutor'),
                    ),
                    DropdownMenuItem(
                      value: AssistantMode.generalChat,
                      child: Text('Chat'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _mode = value);
                    }
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration:
                        const InputDecoration(hintText: 'Ask assistant...'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: state.isLoading ? null : _sendMessage,
                  child: const Text('Send'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      return;
    }
    ref
        .read(assistantControllerProvider.notifier)
        .sendMessage(text: message, mode: _mode);
    _messageController.clear();
  }
}
