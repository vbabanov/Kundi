import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../l10n/l10n.dart';
import '../../../shared/theme/kundi_tokens.dart';
import '../../../shared/widgets/kundi_surface.dart';
import '../application/assistant_controller.dart';
import '../application/kundi_tts_coordinator.dart';
import '../domain/assistant_entity.dart';

class AssistantPage extends ConsumerStatefulWidget {
  const AssistantPage({super.key});

  @override
  ConsumerState<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends ConsumerState<AssistantPage> {
  static const _legacyImeLayoutChannel =
      MethodChannel('com.kundi.kundi_mobile/legacy_ime_layout');

  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onDraftChanged);
    _messageFocus.addListener(_onMessageFocusChanged);
    unawaited(
      ref.read(assistantControllerProvider.notifier).revalidateOnPageOpen(),
    );
  }

  @override
  void dispose() {
    _messageController
      ..removeListener(_onDraftChanged)
      ..dispose();
    _messageFocus
      ..removeListener(_onMessageFocusChanged)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  void _onMessageFocusChanged() {
    if (_messageFocus.hasFocus) {
      unawaited(_prepareLegacyImeLayout());
    }
  }

  Future<void> _prepareLegacyImeLayout() async {
    try {
      await _legacyImeLayoutChannel.invokeMethod<void>('prepareForIme');
    } on MissingPluginException {
      // Non-Android targets and widget tests do not install the host channel.
    } on PlatformException {
      // Input remains usable if a vendor host rejects the compatibility hint.
    }
  }

  Future<void> _focusComposer() async {
    await _prepareLegacyImeLayout();
    if (mounted) _messageFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assistantControllerProvider);
    final speechError = ref.watch(kundiTtsEnabledProvider) &&
        ref.watch(
          kundiTtsCoordinatorProvider.select(
            (state) => state.status == KundiTtsStatus.error,
          ),
        );
    ref.listen(assistantControllerProvider, (previous, next) {
      int visualItems(AsyncValue<AssistantViewState>? value) {
        final view = value?.valueOrNull;
        if (view == null) return 0;
        return view.messages.length +
            (view.pendingText.isNotEmpty ? 1 : 0) +
            (view.isSending ? 1 : 0);
      }

      if (visualItems(next) > visualItems(previous)) _scrollToLatest();
    });

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: KundiGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              _AssistantTopBar(
                enabled: state.hasValue,
                onBack: () => Navigator.of(context).maybePop(),
                onHistory: _showSessions,
                onMenu: _handleMenu,
              ),
              Expanded(
                child: state.when(
                  loading: () => const _AssistantLoading(),
                  error: (_, __) => _LoadError(
                    onRetry: () => ref.invalidate(assistantControllerProvider),
                  ),
                  data: (view) => Column(
                    children: [
                      if (view.isRefreshing)
                        const LinearProgressIndicator(minHeight: 2),
                      Expanded(child: _messageList(view)),
                      if (view.refreshErrorMessage.isNotEmpty)
                        _TransportError(
                          message: view.refreshErrorMessage,
                          onRetry: () => ref
                              .read(assistantControllerProvider.notifier)
                              .retryHistoryRefresh(),
                        ),
                      if (speechError)
                        _TransportError(
                          message: context.l10n.voicePlaybackFailed,
                          onRetry: null,
                        ),
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
              ),
            ],
          ),
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
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      itemCount: view.messages.length + extra,
      itemBuilder: (context, index) {
        var offset = 0;
        if (view.messageCursor.isNotEmpty) {
          if (index == 0) {
            return Center(
              child: TextButton.icon(
                onPressed: () => ref
                    .read(assistantControllerProvider.notifier)
                    .loadOlderMessages(),
                icon: const Icon(Icons.expand_less_rounded, size: 18),
                label: Text(context.l10n.assistantShowPrevious),
              ),
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
    return SizedBox(
      height: 52,
      child: ListView.separated(
        key: const Key('assistant-suggestions'),
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        itemCount: view.suggestions.take(3).length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final text = view.suggestions[index];
          final scheme = Theme.of(context).colorScheme;
          return ActionChip(
            key: Key('assistant-suggestion-$index'),
            avatar: Icon(
              Icons.auto_awesome_rounded,
              size: 16,
              color: scheme.primary,
            ),
            label: Text(
              text,
              style: TextStyle(color: scheme.onSurface),
            ),
            backgroundColor: scheme.kundiElevated,
            side: BorderSide(
              color: scheme.kundiBorder,
            ),
            onPressed: () {
              _messageController
                ..text = text
                ..selection = TextSelection.collapsed(offset: text.length);
              unawaited(_focusComposer());
            },
          );
        },
      ),
    );
  }

  Widget _composer(AssistantViewState view) {
    final canSend =
        !view.isSending && _messageController.text.trim().isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.kundiSurface.withValues(alpha: 0.97),
        border: Border(top: BorderSide(color: scheme.kundiBorder)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.kundiElevated,
                  borderRadius: KundiRadius.lg,
                  border: Border.all(color: scheme.kundiBorder),
                ),
                child: TextField(
                  key: const Key('assistant-text-field'),
                  controller: _messageController,
                  focusNode: _messageFocus,
                  enabled: !view.isSending,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: context.l10n.assistantQuestionHint,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            IconButton.filled(
              key: const Key('assistant-send-button'),
              tooltip: context.l10n.commonSend,
              onPressed: canSend ? _sendMessage : null,
              style: IconButton.styleFrom(
                fixedSize: const Size(48, 48),
              ),
              icon: view.isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_upward_rounded),
            ),
          ],
        ),
      ),
    );
  }

  void _sendMessage() {
    final message = _messageController.text.trim();
    final view = ref.read(assistantControllerProvider).valueOrNull;
    if (message.isEmpty || view?.isSending != false) return;
    _messageController.clear();
    _messageFocus.requestFocus();
    unawaited(
      ref.read(assistantControllerProvider.notifier).sendMessage(message),
    );
    _scrollToLatest();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _showSessions() async {
    if (!ref.read(assistantControllerProvider).hasValue) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Consumer(
        builder: (context, sheetRef, _) {
          final view = sheetRef.watch(assistantControllerProvider).valueOrNull;
          if (view == null) return const _AssistantLoading();
          return _SessionsSheet(
            view: view,
            onOpen: (session) {
              Navigator.of(context).pop();
              sheetRef
                  .read(assistantControllerProvider.notifier)
                  .openSession(session);
            },
            onLoadMore: view.sessionCursor.isEmpty
                ? null
                : () => sheetRef
                    .read(assistantControllerProvider.notifier)
                    .loadMoreSessions(),
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
        icon: const Icon(Icons.delete_outline_rounded),
        title: Text(context.l10n.assistantDeleteTitle),
        content: Text(context.l10n.assistantDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(assistantControllerProvider.notifier)
          .deleteCurrentSession();
    }
  }
}

class _AssistantTopBar extends StatelessWidget {
  const _AssistantTopBar({
    required this.enabled,
    required this.onBack,
    required this.onHistory,
    required this.onMenu,
  });

  final bool enabled;
  final VoidCallback onBack;
  final VoidCallback onHistory;
  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('assistant-top-bar'),
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: scheme.kundiSurface.withValues(alpha: 0.9),
        border: Border(bottom: BorderSide(color: scheme.kundiBorder)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.secondary],
              ),
              shape: BoxShape.circle,
            ),
            child: Text(
              'K',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.assistantTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  context.l10n.assistantSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.kundiTextSecondary,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('assistant-history-button'),
            tooltip: context.l10n.assistantPastChats,
            onPressed: enabled ? onHistory : null,
            icon: const Icon(Icons.history_rounded),
          ),
          PopupMenuButton<String>(
            key: const Key('assistant-menu-button'),
            enabled: enabled,
            tooltip: MaterialLocalizations.of(context).showMenuTooltip,
            onSelected: onMenu,
            itemBuilder: (_) => [
              PopupMenuItem(
                key: const Key('assistant-new-chat-action'),
                value: 'new',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.add_comment_outlined),
                  title: Text(context.l10n.assistantNewChat),
                ),
              ),
              PopupMenuItem(
                key: const Key('assistant-delete-chat-action'),
                value: 'delete',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: Text(context.l10n.assistantDeleteChat),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final AssistantMessageEntity message;

  @override
  Widget build(BuildContext context) {
    return _ConversationRow(
      isUser: message.isUser,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.isUser && message.inputMode == 'voice') ...[
            const _VoiceBadge(),
            const SizedBox(height: 5),
          ],
          SelectableText(message.content),
        ],
      ),
    );
  }
}

class _PendingUserBubble extends StatelessWidget {
  const _PendingUserBubble({required this.text, required this.inputMode});
  final String text;
  final AssistantInputMode inputMode;

  @override
  Widget build(BuildContext context) => _ConversationRow(
        isUser: true,
        pending: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (inputMode == AssistantInputMode.voice) ...[
              const _VoiceBadge(),
              const SizedBox(height: 5),
            ],
            Text(text),
          ],
        ),
      );
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.isUser,
    required this.child,
    this.pending = false,
  });

  final bool isUser;
  final Widget child;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: AnimatedOpacity(
              opacity: pending ? 0.76 : 1,
              duration: const Duration(milliseconds: 150),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 560),
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: isUser ? scheme.primary : scheme.kundiSurface,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isUser ? 18 : 5),
                    bottomRight: Radius.circular(isUser ? 5 : 18),
                  ),
                  border: isUser ? null : Border.all(color: scheme.kundiBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    color: isUser ? scheme.onPrimary : scheme.onSurface,
                    height: 1.38,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KundiMark extends StatelessWidget {
  const _KundiMark({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          'K',
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      );
}

class _VoiceBadge extends StatelessWidget {
  const _VoiceBadge();

  @override
  Widget build(BuildContext context) => Row(
        key: const Key('assistant-voice-message-badge'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.graphic_eq_rounded, size: 14),
          const SizedBox(width: 4),
          Text(
            context.l10n.assistantVoice,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      );
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) => _ConversationRow(
        isUser: false,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 9),
            Text(context.l10n.assistantThinking),
          ],
        ),
      );
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primary, scheme.secondary],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.24),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: Text(
                'K',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              context.l10n.assistantEmpty,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.kundiTextSecondary,
                    height: 1.4,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantLoading extends StatelessWidget {
  const _AssistantLoading();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _KundiMark(color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 14),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
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
    return Container(
      key: const Key('assistant-transport-error'),
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: colors.kundiElevated,
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.45),
        ),
        borderRadius: KundiRadius.lg,
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: colors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onSurface),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(context.l10n.commonRetry),
            ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => KundiStateBody.error(
        label: context.l10n.assistantLoadFailed,
        onRetry: onRetry,
      );
}

class _SessionsSheet extends StatelessWidget {
  const _SessionsSheet({
    required this.view,
    required this.onOpen,
    required this.onLoadMore,
  });

  final AssistantViewState view;
  final ValueChanged<AssistantSessionEntity> onOpen;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      heightFactor: 0.72,
      child: Material(
        color: scheme.kundiSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.kundiBorder,
                borderRadius: KundiRadius.pill,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.assistantPastChats,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.kundiBorder),
            Expanded(
              child: view.sessions.isEmpty
                  ? Center(child: Text(context.l10n.assistantEmpty))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount:
                          view.sessions.length + (onLoadMore == null ? 0 : 1),
                      separatorBuilder: (_, __) => const SizedBox(height: 2),
                      itemBuilder: (context, index) {
                        if (index == view.sessions.length) {
                          return TextButton(
                            onPressed: onLoadMore,
                            child: Text(context.l10n.assistantShowMore),
                          );
                        }
                        final session = view.sessions[index];
                        final selected = session.id == view.activeSession?.id;
                        return ListTile(
                          selected: selected,
                          selectedTileColor:
                              scheme.primary.withValues(alpha: 0.1),
                          leading: CircleAvatar(
                            backgroundColor: selected
                                ? scheme.primary.withValues(alpha: 0.18)
                                : scheme.kundiElevated,
                            child: Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: selected
                                  ? scheme.primary
                                  : scheme.kundiTextSecondary,
                            ),
                          ),
                          title: Text(
                            session.title.isEmpty
                                ? context.l10n.assistantNewChat
                                : session.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            context.l10n
                                .assistantGradeClass(session.gradeLevel),
                          ),
                          trailing: selected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: scheme.primary,
                                )
                              : null,
                          onTap: () => onOpen(session),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
