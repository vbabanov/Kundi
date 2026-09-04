import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../features/auth/application/auth_controller.dart';
import '../../../shared/providers/providers.dart';
import '../../kundi_behavior/application/kundi_behavior_controller.dart';
import '../../kundi_behavior/domain/kundi_behavior_event.dart';
import '../assistant_feature.dart';
import '../data/assistant_repository_impl.dart';
import '../domain/assistant_entity.dart';
import '../domain/assistant_repository.dart';

final assistantRepositoryProvider = Provider<AssistantRepository>((ref) {
  return AssistantRepositoryImpl(apiClient: ref.watch(apiClientProvider));
});

final assistantControllerProvider =
    AsyncNotifierProvider<AssistantController, AssistantViewState>(
  AssistantController.new,
);

class AssistantViewState {
  const AssistantViewState({
    this.sessions = const <AssistantSessionEntity>[],
    this.messages = const <AssistantMessageEntity>[],
    this.activeSession,
    this.sessionCursor = '',
    this.messageCursor = '',
    this.suggestions = const <String>[],
    this.isSending = false,
    this.pendingText = '',
    this.errorMessage = '',
    this.retryText = '',
    this.retryClientMessageId = '',
  });

  final List<AssistantSessionEntity> sessions;
  final List<AssistantMessageEntity> messages;
  final AssistantSessionEntity? activeSession;
  final String sessionCursor;
  final String messageCursor;
  final List<String> suggestions;
  final bool isSending;
  final String pendingText;
  final String errorMessage;
  final String retryText;
  final String retryClientMessageId;

  AssistantViewState copyWith({
    List<AssistantSessionEntity>? sessions,
    List<AssistantMessageEntity>? messages,
    AssistantSessionEntity? activeSession,
    bool clearActiveSession = false,
    String? sessionCursor,
    String? messageCursor,
    List<String>? suggestions,
    bool? isSending,
    String? pendingText,
    String? errorMessage,
    String? retryText,
    String? retryClientMessageId,
  }) {
    return AssistantViewState(
      sessions: sessions ?? this.sessions,
      messages: messages ?? this.messages,
      activeSession:
          clearActiveSession ? null : activeSession ?? this.activeSession,
      sessionCursor: sessionCursor ?? this.sessionCursor,
      messageCursor: messageCursor ?? this.messageCursor,
      suggestions: suggestions ?? this.suggestions,
      isSending: isSending ?? this.isSending,
      pendingText: pendingText ?? this.pendingText,
      errorMessage: errorMessage ?? this.errorMessage,
      retryText: retryText ?? this.retryText,
      retryClientMessageId: retryClientMessageId ?? this.retryClientMessageId,
    );
  }
}

class AssistantController extends AsyncNotifier<AssistantViewState> {
  static const _genericSuggestions = <String>[
    'Объясни тему',
    'Помоги сделать первый шаг',
    'Проверь мой ответ',
  ];

  final Uuid _uuid = const Uuid();

  @override
  Future<AssistantViewState> build() async {
    if (!ref.watch(kundiAssistantEnabledProvider)) {
      return const AssistantViewState();
    }
    final token = _accessToken();
    final repository = ref.read(assistantRepositoryProvider);
    final page = await repository.listSessions(accessToken: token);
    final active = page.items.isEmpty
        ? await repository.createSession(accessToken: token)
        : page.items.first;
    final messages = await repository.listMessages(
      accessToken: token,
      sessionId: active.id,
    );
    final sessions =
        page.items.isEmpty ? <AssistantSessionEntity>[active] : page.items;
    return AssistantViewState(
      sessions: sessions,
      activeSession: active,
      messages: _chronological(messages.items),
      sessionCursor: page.nextCursor,
      messageCursor: messages.nextCursor,
      suggestions: _genericSuggestions,
    );
  }

  Future<void> createNewSession() async {
    final previous = state.valueOrNull ?? const AssistantViewState();
    state = const AsyncLoading<AssistantViewState>();
    state = await AsyncValue.guard(() async {
      final session = await ref
          .read(assistantRepositoryProvider)
          .createSession(accessToken: _accessToken());
      return previous.copyWith(
        sessions: <AssistantSessionEntity>[session, ...previous.sessions],
        activeSession: session,
        messages: const <AssistantMessageEntity>[],
        messageCursor: '',
        suggestions: _genericSuggestions,
        errorMessage: '',
        retryText: '',
        retryClientMessageId: '',
      );
    });
  }

  Future<void> openSession(AssistantSessionEntity session) async {
    final previous = state.valueOrNull ?? const AssistantViewState();
    state = const AsyncLoading<AssistantViewState>();
    state = await AsyncValue.guard(() async {
      final page = await ref.read(assistantRepositoryProvider).listMessages(
            accessToken: _accessToken(),
            sessionId: session.id,
          );
      return previous.copyWith(
        activeSession: session,
        messages: _chronological(page.items),
        messageCursor: page.nextCursor,
        suggestions: _genericSuggestions,
        errorMessage: '',
      );
    });
  }

  Future<void> loadOlderMessages() async {
    final current = state.valueOrNull;
    if (current == null ||
        current.activeSession == null ||
        current.messageCursor.isEmpty) {
      return;
    }
    final page = await ref.read(assistantRepositoryProvider).listMessages(
          accessToken: _accessToken(),
          sessionId: current.activeSession!.id,
          cursor: current.messageCursor,
        );
    final latest = state.valueOrNull;
    if (latest?.activeSession?.id != current.activeSession!.id) return;
    state = AsyncData(latest!.copyWith(
      messages: _mergeMessages(page.items, latest.messages),
      messageCursor: page.nextCursor,
    ));
  }

  Future<void> loadMoreSessions() async {
    final current = state.valueOrNull;
    if (current == null || current.sessionCursor.isEmpty) return;
    final page = await ref.read(assistantRepositoryProvider).listSessions(
          accessToken: _accessToken(),
          cursor: current.sessionCursor,
        );
    final latest = state.valueOrNull ?? current;
    state = AsyncData(latest.copyWith(
      sessions: _mergeSessions(latest.sessions, page.items),
      sessionCursor: page.nextCursor,
    ));
  }

  Future<void> sendMessage(String text, {String? clientMessageId}) async {
    final normalized = text.trim();
    final current = state.valueOrNull;
    if (normalized.isEmpty || current == null || current.isSending) return;
    final active = current.activeSession;
    if (active == null) return;
    final requestID = clientMessageId ?? _uuid.v4();
    state = AsyncData(current.copyWith(
      isSending: true,
      pendingText: normalized,
      errorMessage: '',
      retryText: normalized,
      retryClientMessageId: requestID,
    ));
    _behavior(KundiBehaviorEventType.assistantQuestionSubmitted, requestID);
    try {
      final result =
          await ref.read(assistantRepositoryProvider).sendSessionMessage(
                accessToken: _accessToken(),
                sessionId: active.id,
                clientMessageId: requestID,
                text: normalized,
              );
      final latest = state.valueOrNull ?? current;
      state = AsyncData(latest.copyWith(
        messages: _mergeMessages(
          latest.messages,
          <AssistantMessageEntity>[
            result.userMessage,
            result.assistantMessage,
          ],
        ),
        suggestions: result.suggestions.isEmpty
            ? latest.suggestions
            : result.suggestions,
        isSending: false,
        pendingText: '',
        errorMessage: '',
        retryText: '',
        retryClientMessageId: '',
      ));
      _neutralBehavior();
    } catch (_) {
      final latest = state.valueOrNull ?? current;
      state = AsyncData(latest.copyWith(
        isSending: false,
        pendingText: '',
        errorMessage: 'Не удалось отправить сообщение. Проверьте соединение.',
      ));
      _behavior(KundiBehaviorEventType.assistantFailure, requestID);
    }
  }

  Future<void> retryLastMessage() async {
    final current = state.valueOrNull;
    if (current == null || current.retryText.isEmpty) return;
    await sendMessage(
      current.retryText,
      clientMessageId: current.retryClientMessageId,
    );
  }

  Future<void> deleteCurrentSession() async {
    final current = state.valueOrNull;
    final active = current?.activeSession;
    if (current == null || active == null) return;
    await ref.read(assistantRepositoryProvider).deleteSession(
          accessToken: _accessToken(),
          sessionId: active.id,
        );
    final remaining = current.sessions
        .where((session) => session.id != active.id)
        .toList(growable: false);
    if (remaining.isEmpty) {
      state = AsyncData(current.copyWith(
        sessions: const <AssistantSessionEntity>[],
        messages: const <AssistantMessageEntity>[],
        clearActiveSession: true,
      ));
      await createNewSession();
      return;
    }
    state = AsyncData(current.copyWith(sessions: remaining));
    await openSession(remaining.first);
  }

  String _accessToken() {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null || session.accessToken.trim().isEmpty) {
      throw StateError('User must login before assistant can be used.');
    }
    return session.accessToken;
  }

  void _behavior(KundiBehaviorEventType type, String requestID) {
    if (!ref.read(kundiBehaviorCoreEnabledProvider)) return;
    ref.read(kundiBehaviorControllerProvider.notifier).dispatch(
          KundiBehaviorEvent(
            type: type,
            id: 'assistant:$requestID:${type.name}',
            occurredAt: DateTime.now().toUtc(),
            fingerprint: 'assistant:$requestID:${type.name}',
          ),
        );
  }

  void _neutralBehavior() {
    if (!ref.read(kundiBehaviorCoreEnabledProvider)) return;
    ref.read(kundiBehaviorControllerProvider.notifier).dismiss();
  }

  static List<AssistantMessageEntity> _chronological(
      List<AssistantMessageEntity> items) {
    final out = List<AssistantMessageEntity>.from(items)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  static List<AssistantMessageEntity> _mergeMessages(
    List<AssistantMessageEntity> first,
    List<AssistantMessageEntity> second,
  ) {
    final byID = <String, AssistantMessageEntity>{};
    for (final item in <AssistantMessageEntity>[...first, ...second]) {
      byID[item.id] = item;
    }
    return _chronological(byID.values.toList(growable: false));
  }

  static List<AssistantSessionEntity> _mergeSessions(
    List<AssistantSessionEntity> first,
    List<AssistantSessionEntity> second,
  ) {
    final byID = <String, AssistantSessionEntity>{};
    for (final item in <AssistantSessionEntity>[...first, ...second]) {
      byID[item.id] = item;
    }
    final out = byID.values.toList(growable: false)
      ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    return out;
  }
}
