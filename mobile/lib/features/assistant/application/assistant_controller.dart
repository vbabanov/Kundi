import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../features/auth/application/auth_controller.dart';
import '../../../shared/providers/providers.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../runtimes/kundi_system_speech/kundi_voice_qa_telemetry.dart';
import '../../kundi_behavior/application/kundi_behavior_controller.dart';
import '../../kundi_behavior/domain/kundi_behavior_event.dart';
import '../../settings/application/settings_controller.dart';
import '../../settings/domain/settings_entity.dart';
import '../assistant_feature.dart';
import '../data/assistant_repository_impl.dart';
import '../domain/assistant_entity.dart';
import '../domain/assistant_repository.dart';
import 'kundi_tts_coordinator.dart';

final assistantRepositoryProvider = Provider<AssistantRepository>((ref) {
  const qaBaseUrl = String.fromEnvironment(
    'KUNDI_ASSISTANT_QA_BASE_URL',
    defaultValue: '',
  );
  final apiClient =
      kDebugMode && kundiVoiceQaTelemetryEnabled && qaBaseUrl.isNotEmpty
          ? ApiClient(baseUrl: qaBaseUrl)
          : ref.watch(apiClientProvider);
  return AssistantRepositoryImpl(apiClient: apiClient);
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
    this.pendingInputMode = AssistantInputMode.text,
    this.errorMessage = '',
    this.retryText = '',
    this.retryClientMessageId = '',
    this.retryInputMode = AssistantInputMode.text,
    this.isRefreshing = false,
    this.refreshErrorMessage = '',
  });

  final List<AssistantSessionEntity> sessions;
  final List<AssistantMessageEntity> messages;
  final AssistantSessionEntity? activeSession;
  final String sessionCursor;
  final String messageCursor;
  final List<String> suggestions;
  final bool isSending;
  final String pendingText;
  final AssistantInputMode pendingInputMode;
  final String errorMessage;
  final String retryText;
  final String retryClientMessageId;
  final AssistantInputMode retryInputMode;
  final bool isRefreshing;
  final String refreshErrorMessage;

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
    AssistantInputMode? pendingInputMode,
    String? errorMessage,
    String? retryText,
    String? retryClientMessageId,
    AssistantInputMode? retryInputMode,
    bool? isRefreshing,
    String? refreshErrorMessage,
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
      pendingInputMode: pendingInputMode ?? this.pendingInputMode,
      errorMessage: errorMessage ?? this.errorMessage,
      retryText: retryText ?? this.retryText,
      retryClientMessageId: retryClientMessageId ?? this.retryClientMessageId,
      retryInputMode: retryInputMode ?? this.retryInputMode,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      refreshErrorMessage: refreshErrorMessage ?? this.refreshErrorMessage,
    );
  }
}

class AssistantController extends AsyncNotifier<AssistantViewState> {
  final Uuid _uuid = const Uuid();
  Future<void>? _historyRefresh;
  AssistantSessionEntity? _retryRefreshSession;

  @override
  Future<AssistantViewState> build() async {
    // Rebuild presentation-owned suggestions and errors when the app locale
    // changes. Messages are reloaded; language switching never deletes them.
    ref.watch(
      settingsControllerProvider.select(
        (value) => value.valueOrNull?.language ?? AppLanguage.ru,
      ),
    );
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
      messages: _mergeMessages(
        const <AssistantMessageEntity>[],
        messages.items,
      ),
      sessionCursor: page.nextCursor,
      messageCursor: messages.nextCursor,
      suggestions: _genericSuggestions(),
    );
  }

  Future<void> createNewSession() async {
    await _cancelSpeech();
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
        suggestions: _genericSuggestions(),
        errorMessage: '',
        retryText: '',
        retryClientMessageId: '',
      );
    });
  }

  Future<void> openSession(AssistantSessionEntity session) async {
    await _cancelSpeech();
    final previous = state.valueOrNull;
    if (previous == null) return;
    final pending = _historyRefresh;
    if (pending != null) return pending;
    _retryRefreshSession = session;
    state = AsyncData(previous.copyWith(
      isRefreshing: true,
      refreshErrorMessage: '',
    ));
    final refresh = () async {
      try {
        final page = await ref.read(assistantRepositoryProvider).listMessages(
              accessToken: _accessToken(),
              sessionId: session.id,
            );
        final latest = state.valueOrNull ?? previous;
        state = AsyncData(latest.copyWith(
          activeSession: session,
          messages: _mergeMessages(
            const <AssistantMessageEntity>[],
            page.items,
          ),
          messageCursor: page.nextCursor,
          suggestions: _genericSuggestions(),
          errorMessage: '',
          isRefreshing: false,
          refreshErrorMessage: '',
        ));
        _retryRefreshSession = null;
      } catch (_) {
        final latest = state.valueOrNull ?? previous;
        state = AsyncData(latest.copyWith(
          isRefreshing: false,
          refreshErrorMessage: _l10n().assistantHistoryRefreshFailed,
        ));
      }
    }();
    _historyRefresh = refresh;
    try {
      await refresh;
    } finally {
      if (identical(_historyRefresh, refresh)) _historyRefresh = null;
    }
  }

  Future<void> refreshActiveSession() async {
    final active = state.valueOrNull?.activeSession;
    if (active != null) await openSession(active);
  }

  Future<void> revalidateOnPageOpen() async {
    await refreshActiveSession();
  }

  Future<void> retryHistoryRefresh() async {
    final session = _retryRefreshSession;
    if (session != null) await openSession(session);
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

  Future<void> sendMessage(
    String text, {
    String? clientMessageId,
    AssistantInputMode inputMode = AssistantInputMode.text,
  }) async {
    final normalized = text.trim();
    final current = state.valueOrNull;
    if (normalized.isEmpty || current == null || current.isSending) return;
    final active = current.activeSession;
    if (active == null) return;
    final requestID = clientMessageId ?? _uuid.v4();
    final tts = ref.read(kundiTtsEnabledProvider)
        ? ref.read(kundiTtsCoordinatorProvider.notifier)
        : null;
    final speechEpoch = tts?.epoch;
    state = AsyncData(current.copyWith(
      isSending: true,
      pendingText: normalized,
      pendingInputMode: inputMode,
      errorMessage: '',
      retryText: normalized,
      retryClientMessageId: requestID,
      retryInputMode: inputMode,
    ));
    _behavior(KundiBehaviorEventType.assistantQuestionSubmitted, requestID);
    try {
      final result =
          await ref.read(assistantRepositoryProvider).sendSessionMessage(
                accessToken: _accessToken(),
                sessionId: active.id,
                clientMessageId: requestID,
                text: normalized,
                inputMode: inputMode,
              );
      final latest = state.valueOrNull ?? current;
      final updatedSession = result.session;
      state = AsyncData(latest.copyWith(
        messages: _mergeMessages(
          latest.messages,
          <AssistantMessageEntity>[
            result.userMessage,
            result.assistantMessage,
          ],
        ),
        suggestions: _genericSuggestions(),
        activeSession: updatedSession ?? latest.activeSession,
        sessions: updatedSession == null
            ? latest.sessions
            : _mergeSessions(latest.sessions, <AssistantSessionEntity>[
                updatedSession,
              ]),
        isSending: false,
        pendingText: '',
        pendingInputMode: AssistantInputMode.text,
        errorMessage: '',
        retryText: '',
        retryClientMessageId: '',
        retryInputMode: AssistantInputMode.text,
      ));
      _neutralBehavior();
      if (inputMode == AssistantInputMode.voice &&
          tts != null &&
          speechEpoch != null) {
        unawaited(tts.speakResponse(result, expectedEpoch: speechEpoch));
      }
    } catch (error) {
      final latest = state.valueOrNull ?? current;
      final failure = _sendFailure(error);
      if (failure.refreshAuthorization) {
        ref.invalidate(authControllerProvider);
      }
      state = AsyncData(latest.copyWith(
        isSending: false,
        pendingText: '',
        pendingInputMode: AssistantInputMode.text,
        errorMessage: failure.message,
        retryText: failure.canRetry ? normalized : '',
        retryClientMessageId: failure.canRetry ? requestID : '',
        retryInputMode: failure.canRetry ? inputMode : AssistantInputMode.text,
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
      inputMode: current.retryInputMode,
    );
  }

  Future<void> deleteCurrentSession() async {
    await _cancelSpeech();
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

  Future<void> _cancelSpeech() async {
    if (ref.read(kundiTtsEnabledProvider)) {
      await ref.read(kundiTtsCoordinatorProvider.notifier).cancel();
    }
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

  List<String> _genericSuggestions() {
    final l10n = _l10n();
    return <String>[
      l10n.assistantSuggestionExplain,
      l10n.assistantSuggestionFirstStep,
      l10n.assistantSuggestionCheck,
    ];
  }

  _AssistantSendFailure _sendFailure(Object error) {
    final l10n = _l10n();
    if (error is AppException) {
      switch (error.code) {
        case 'assistant_rate_limited':
        case 'assistant_provider_rate_limited':
          return _AssistantSendFailure(
            message: l10n.assistantRateLimited,
            canRetry: true,
          );
        case 'assistant_disabled':
          return _AssistantSendFailure(
            message: l10n.assistantUnavailable,
          );
        case 'assistant_provider_unavailable':
        case 'assistant_request_timeout':
        case 'assistant_safety_unavailable':
          return _AssistantSendFailure(
            message: l10n.assistantTemporaryFailure,
            canRetry: true,
          );
        case 'unauthorized':
        case 'assistant_auth_required':
          return const _AssistantSendFailure(refreshAuthorization: true);
        case 'assistant_network_error':
          return _AssistantSendFailure(
            message: l10n.assistantSendFailed,
            canRetry: true,
          );
      }
      if (_isValidationCode(error.code)) {
        return _AssistantSendFailure(message: error.message);
      }
    }
    return _AssistantSendFailure(
      message: l10n.assistantSendFailed,
    );
  }

  AppLocalizations _l10n() {
    final language =
        ref.read(settingsControllerProvider).valueOrNull?.language ??
            AppLanguage.ru;
    return lookupAppLocalizations(Locale(language.name));
  }

  static bool _isValidationCode(String code) {
    return code == 'invalid_json' ||
        code == 'assistant_empty_text' ||
        code.endsWith('_invalid') ||
        code.endsWith('_required') ||
        code.contains('_too_long') ||
        code.contains('_too_large');
  }
}

class _AssistantSendFailure {
  const _AssistantSendFailure({
    this.message = '',
    this.canRetry = false,
    this.refreshAuthorization = false,
  });

  final String message;
  final bool canRetry;
  final bool refreshAuthorization;
}
