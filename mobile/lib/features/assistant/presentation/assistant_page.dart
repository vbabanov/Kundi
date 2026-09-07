import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/assistant_controller.dart';
import '../application/kundi_tts_coordinator.dart';
import '../domain/assistant_entity.dart';

class AssistantPage extends ConsumerStatefulWidget {
  const AssistantPage({super.key});

  @override
  ConsumerState<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends ConsumerState<AssistantPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    unawaited(
      ref.read(assistantControllerProvider.notifier).revalidateOnPageOpen(),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assistantControllerProvider);
    final speechError = ref.watch(kundiTtsEnabledProvider)
        ? ref.watch(kundiTtsCoordinatorProvider.select((s) => s.errorMessage))
        : '';
    ref.listen(assistantControllerProvider, (previous, next) {
      final before = previous?.valueOrNull?.messages.length ?? 0;
      final after = next.valueOrNull?.messages.length ?? 0;
      if (after > before) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Спросите Kundi'),
        actions: [
          IconButton(
            key: const Key('assistant-history-button'),
            tooltip: 'Прошлые диалоги',
            onPressed: state.hasValue ? _showSessions : null,
            icon: const Icon(Icons.history_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'new', child: Text('Новый диалог')),
              PopupMenuItem(value: 'delete', child: Text('Удалить диалог')),
            ],
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _LoadError(
          onRetry: () => ref.invalidate(assistantControllerProvider),
        ),
        data: (view) => Column(
          children: [
            if (view.isRefreshing) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: _messageList(view)),
            if (view.refreshErrorMessage.isNotEmpty)
              _TransportError(
                message: view.refreshErrorMessage,
                onRetry: () => ref
                    .read(assistantControllerProvider.notifier)
                    .retryHistoryRefresh(),
              ),
            if (speechError.isNotEmpty)
              _TransportError(message: speechError, onRetry: null),
            if (view.errorMessage.isNotEmpty)
              _TransportError(
                message: view.errorMessage,
                onRetry: view.retryText.isEmpty
                    ? null
                    : () => ref
                        .read(assistantControllerProvider.notifier)
                        .retryLastMessage(),
              ),
            _suggestions(view),
            _composer(view),
          ],
        ),
      ),
    );
  }

  Widget _messageList(AssistantViewState view) {
    final hasPending = view.pendingText.isNotEmpty;
    if (view.messages.isEmpty && !hasPending && !view.isSending) {
      return const _EmptyConversation();
    }
    final extra = (view.messageCursor.isNotEmpty ? 1 : 0) +
        (hasPending ? 1 : 0) +
        (view.isSending ? 1 : 0);
    return ListView.builder(
      key: const Key('assistant-message-list'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: view.messages.length + extra,
      itemBuilder: (context, index) {
        var offset = 0;
        if (view.messageCursor.isNotEmpty) {
          if (index == 0) {
            return TextButton(
              onPressed: () => ref
                  .read(assistantControllerProvider.notifier)
                  .loadOlderMessages(),
              child: const Text('Показать предыдущие сообщения'),
            );
          }
          offset = 1;
        }
        final messageIndex = index - offset;
        if (messageIndex < view.messages.length) {
          return _MessageBubble(message: view.messages[messageIndex]);
        }
        final tailIndex = messageIndex - view.messages.length;
        if (hasPending && tailIndex == 0) {
          return _PendingUserBubble(
            text: view.pendingText,
            inputMode: view.pendingInputMode,
          );
        }
        return const _ThinkingBubble();
      },
    );
  }

  Widget _suggestions(AssistantViewState view) {
    if (view.suggestions.isEmpty || view.isSending) {
      return const SizedBox.shrink();
    }
    return SingleChildScrollView(
      key: const Key('assistant-suggestions'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(
        children: view.suggestions.take(3).map((text) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              label: Text(text),
              onPressed: () => _messageController.text = text,
            ),
          );
        }).toList(growable: false),
      ),
    );
  }

  Widget _composer(AssistantViewState view) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const Key('assistant-text-field'),
                controller: _messageController,
                enabled: !view.isSending,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Напишите вопрос…',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const Key('assistant-send-button'),
              tooltip: 'Отправить',
              onPressed: view.isSending ? null : _sendMessage,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }

  void _sendMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    _messageController.clear();
    ref.read(assistantControllerProvider.notifier).sendMessage(message);
  }

  Future<void> _showSessions() async {
    if (!ref.read(assistantControllerProvider).hasValue) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Consumer(
        builder: (context, sheetRef, _) {
          final view = sheetRef.watch(assistantControllerProvider).valueOrNull;
          if (view == null) {
            return const SafeArea(
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(title: Text('Прошлые диалоги')),
                ...view.sessions.map((session) => ListTile(
                      selected: session.id == view.activeSession?.id,
                      title: Text(session.title.isEmpty
                          ? 'Новый диалог'
                          : session.title),
                      subtitle: Text('${session.gradeLevel} класс'),
                      onTap: () {
                        Navigator.of(context).pop();
                        sheetRef
                            .read(assistantControllerProvider.notifier)
                            .openSession(session);
                      },
                    )),
                if (view.sessionCursor.isNotEmpty)
                  TextButton(
                    onPressed: () => sheetRef
                        .read(assistantControllerProvider.notifier)
                        .loadMoreSessions(),
                    child: const Text('Показать ещё'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleMenu(String value) async {
    if (value == 'new') {
      await ref.read(assistantControllerProvider.notifier).createNewSession();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить диалог?'),
        content: const Text('Историю этого диалога нельзя будет восстановить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(assistantControllerProvider.notifier)
          .deleteCurrentSession();
    }
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final AssistantMessageEntity message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: message.isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.isUser && message.inputMode == 'voice') ...[
              const Row(
                key: Key('assistant-voice-message-badge'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic_rounded, size: 14),
                  SizedBox(width: 4),
                  Text('Голосом'),
                ],
              ),
              const SizedBox(height: 4),
            ],
            SelectableText(message.content),
          ],
        ),
      ),
    );
  }
}

class _PendingUserBubble extends StatelessWidget {
  const _PendingUserBubble({required this.text, required this.inputMode});
  final String text;
  final AssistantInputMode inputMode;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (inputMode == AssistantInputMode.voice) ...[
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mic_rounded, size: 14),
                    SizedBox(width: 4),
                    Text('Голосом'),
                  ],
                ),
                const SizedBox(height: 4),
              ],
              Text(text),
            ],
          ),
        ),
      );
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) => const Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('Kundi думает…'),
            ],
          ),
        ),
      );
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Задайте вопрос — Kundi объяснит тему, даст подсказку или проверит ваш шаг.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}

class _TransportError extends StatelessWidget {
  const _TransportError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                child: const Text('Повторить'),
              ),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Не удалось загрузить диалог.'),
            const SizedBox(height: 8),
            FilledButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      );
}
