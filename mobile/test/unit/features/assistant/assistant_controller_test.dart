import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/errors/app_exception.dart';
import 'package:kundi_mobile/features/assistant/application/assistant_controller.dart';
import 'package:kundi_mobile/features/assistant/application/kundi_tts_coordinator.dart';
import 'kundi_tts_coordinator_test.dart' as speech_test;
import 'package:kundi_mobile/features/assistant/assistant_feature.dart';
import 'package:kundi_mobile/features/assistant/domain/assistant_entity.dart';
import 'package:kundi_mobile/features/assistant/domain/assistant_repository.dart';
import 'package:kundi_mobile/features/auth/application/auth_controller.dart';
import 'package:kundi_mobile/features/auth/domain/auth_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'only foreground voice send triggers TTS; history and failure preserve text',
      () async {
    final wire = speech_test.FakeTts();
    final reply = speech_test.result();
    final tts = KundiTtsCoordinator(
        enabled: true,
        transport: wire,
        authorize: (message) async => speech_test.authorization(message));
    final repository = _FakeAssistantRepository(sessions: [
      _session(
          id: 's',
          locale: 'ru-RU',
          title: '',
          lastMessageAt: DateTime.utc(2026))
    ], result: reply);
    final container = ProviderContainer(overrides: [
      kundiAssistantEnabledProvider.overrideWithValue(true),
      kundiVoiceInputEnabledProvider.overrideWithValue(true),
      kundiTtsEnabledProvider.overrideWithValue(true),
      kundiTtsCoordinatorProvider.overrideWith((ref) => tts),
      assistantRepositoryProvider.overrideWithValue(repository),
      authControllerProvider.overrideWith(_FakeAuthController.new),
    ]);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await container.read(assistantControllerProvider.future);
    final controller = container.read(assistantControllerProvider.notifier);
    expect(wire.texts, isEmpty);
    await controller.sendMessage('typed');
    expect(wire.texts, isEmpty);
    await controller.sendMessage('voice', inputMode: AssistantInputMode.voice);
    await Future<void>.delayed(Duration.zero);
    expect(wire.texts, [reply.assistantMessage.content]);
    await tts.cancel();
    await controller.openSession(repository.sessions.first);
    expect(wire.texts.length, 1);
    expect(repository.sentClientMessageIds.length, 2);
  });
  test('send applies returned session snapshot and sorts sessions', () async {
    final old = _session(
      id: 'active',
      locale: 'kk-KZ',
      title: '',
      lastMessageAt: DateTime.utc(2026, 9, 4, 10),
    );
    final other = _session(
      id: 'other',
      locale: 'ru-KZ',
      title: 'Бұрынғы диалог',
      lastMessageAt: DateTime.utc(2026, 9, 4, 11),
    );
    final updated = _session(
      id: 'active',
      locale: 'kk-KZ',
      title: 'Бөлшектерді түсіндіру',
      lastMessageAt: DateTime.utc(2026, 9, 4, 12),
    );
    final repository = _FakeAssistantRepository(
      sessions: <AssistantSessionEntity>[old, other],
      result: _result(session: updated),
    );
    final container = await _container(repository);
    addTearDown(container.dispose);

    var state = await container.read(assistantControllerProvider.future);
    // Stored session locale is intentionally ignored: app locale is the
    // source of truth, and this container uses the Russian default.
    expect(state.suggestions.first, 'Объясни тему');
    await container
        .read(assistantControllerProvider.notifier)
        .sendMessage('Бөлшектерді түсіндір');
    state = container.read(assistantControllerProvider).requireValue;

    expect(state.activeSession?.title, 'Бөлшектерді түсіндіру');
    expect(state.sessions.first.id, 'active');
    expect(state.sessions.first.title, 'Бөлшектерді түсіндіру');
    expect(repository.listSessionCalls, 1);
  });

  test('missing session snapshot keeps old backend fallback behavior',
      () async {
    final active = _session(
      id: 'active',
      locale: 'ru-KZ',
      title: 'Старый заголовок',
      lastMessageAt: DateTime.utc(2026, 9, 4, 10),
    );
    final repository = _FakeAssistantRepository(
      sessions: <AssistantSessionEntity>[active],
      result: _result(),
    );
    final container = await _container(repository);
    addTearDown(container.dispose);
    await container
        .read(assistantControllerProvider.notifier)
        .sendMessage('Вопрос');
    final state = container.read(assistantControllerProvider).requireValue;
    expect(state.activeSession?.title, 'Старый заголовок');
    expect(state.sessions.single.title, 'Старый заголовок');
  });

  test('typed send errors expose only safe messages and safe retry', () async {
    final cases = <({AppException error, String message, bool retry})>[
      (
        error: const AppException('assistant_rate_limited', 'raw'),
        message:
            'Слишком много запросов. Немного подождите и попробуйте снова.',
        retry: true,
      ),
      (
        error: const AppException('assistant_disabled', 'raw'),
        message: 'Kundi пока недоступна.',
        retry: false,
      ),
      (
        error: const AppException('assistant_provider_unavailable', 'raw'),
        message: 'Kundi временно не смогла ответить. Попробуйте ещё раз.',
        retry: true,
      ),
      (
        error: const AppException(
          'assistant_text_too_long',
          'Сообщение слишком длинное.',
        ),
        message: 'Сообщение слишком длинное.',
        retry: false,
      ),
      (
        error: const AppException('assistant_network_error', 'raw'),
        message: 'Не удалось отправить сообщение. Проверьте соединение.',
        retry: true,
      ),
    ];

    for (final item in cases) {
      final repository = _FakeAssistantRepository(
        sessions: <AssistantSessionEntity>[
          _session(
            id: 'active',
            locale: 'ru-KZ',
            title: '',
            lastMessageAt: DateTime.utc(2026, 9, 4),
          ),
        ],
        error: item.error,
      );
      final container = await _container(repository);
      await container
          .read(assistantControllerProvider.notifier)
          .sendMessage('Вопрос');
      final state = container.read(assistantControllerProvider).requireValue;
      expect(state.errorMessage, item.message, reason: item.error.code);
      expect(state.retryText.isNotEmpty, item.retry, reason: item.error.code);
      if (item.retry) {
        expect(state.retryClientMessageId, repository.lastClientMessageId);
      }
      container.dispose();
    }
  });

  test('authorization error returns control to auth flow without retry',
      () async {
    _FakeAuthController.buildCount = 0;
    final repository = _FakeAssistantRepository(
      sessions: <AssistantSessionEntity>[
        _session(
          id: 'active',
          locale: 'ru-KZ',
          title: '',
          lastMessageAt: DateTime.utc(2026, 9, 4),
        ),
      ],
      error: const AppException('unauthorized', 'raw'),
    );
    final container = await _container(repository);
    addTearDown(container.dispose);
    await container
        .read(assistantControllerProvider.notifier)
        .sendMessage('Вопрос');
    final state = container.read(assistantControllerProvider).requireValue;
    expect(state.errorMessage, isEmpty);
    expect(state.retryText, isEmpty);
    await container.read(authControllerProvider.future);
    expect(_FakeAuthController.buildCount, 2);
  });

  test('retry reuses the original client message UUID', () async {
    final repository = _FakeAssistantRepository(
      sessions: <AssistantSessionEntity>[
        _session(
          id: 'active',
          locale: 'ru-KZ',
          title: '',
          lastMessageAt: DateTime.utc(2026, 9, 4),
        ),
      ],
      result: _result(),
      error: const AppException('assistant_network_error', 'raw'),
    );
    final container = await _container(repository);
    addTearDown(container.dispose);
    final controller = container.read(assistantControllerProvider.notifier);
    await controller.sendMessage(
      'Вопрос',
      inputMode: AssistantInputMode.voice,
    );
    final originalID = repository.lastClientMessageId;
    expect(repository.lastInputMode, AssistantInputMode.voice);
    repository.error = null;
    await controller.retryLastMessage();
    expect(repository.sentClientMessageIds, <String>[originalID, originalID]);
    expect(repository.lastInputMode, AssistantInputMode.voice);
  });

  test('revalidation failure preserves stale messages and active session',
      () async {
    final session = _session(
      id: 'active',
      locale: 'kk-KZ',
      title: 'Бөлшектер',
      lastMessageAt: DateTime.utc(2026, 9, 5),
    );
    final oldMessage = _message(
      'old-message',
      'assistant',
      DateTime.utc(2026, 9, 5, 10),
    );
    final repository = _FakeAssistantRepository(
      sessions: <AssistantSessionEntity>[session],
      result: _result(),
      messages: <AssistantMessageEntity>[oldMessage],
    );
    final container = await _container(repository);
    addTearDown(container.dispose);
    repository.messageError =
        const AppException('assistant_network_error', 'raw');

    await container
        .read(assistantControllerProvider.notifier)
        .refreshActiveSession();
    final state = container.read(assistantControllerProvider).requireValue;

    expect(state.messages, <AssistantMessageEntity>[oldMessage]);
    expect(state.activeSession?.id, 'active');
    expect(state.isRefreshing, isFalse);
    expect(state.refreshErrorMessage, 'Не удалось обновить историю');
    expect(repository.listMessageCalls, 2);
  });

  test('history retry replaces stale data and clears transient error',
      () async {
    final session = _session(
      id: 'active',
      locale: 'ru-KZ',
      title: 'Диалог',
      lastMessageAt: DateTime.utc(2026, 9, 5),
    );
    final oldMessage = _message(
      'old-message',
      'assistant',
      DateTime.utc(2026, 9, 5, 10),
    );
    final newMessage = _message(
      'new-message',
      'assistant',
      DateTime.utc(2026, 9, 5, 11),
    );
    final repository = _FakeAssistantRepository(
      sessions: <AssistantSessionEntity>[session],
      result: _result(),
      messages: <AssistantMessageEntity>[oldMessage],
    );
    final container = await _container(repository);
    addTearDown(container.dispose);
    final controller = container.read(assistantControllerProvider.notifier);
    repository.messageError =
        const AppException('assistant_network_error', 'raw');
    await controller.refreshActiveSession();
    repository
      ..messageError = null
      ..messages = <AssistantMessageEntity>[oldMessage, newMessage, newMessage];

    await controller.retryHistoryRefresh();
    final state = container.read(assistantControllerProvider).requireValue;

    expect(state.messages.map((message) => message.id),
        <String>['old-message', 'new-message']);
    expect(state.activeSession?.id, 'active');
    expect(state.refreshErrorMessage, isEmpty);
    expect(repository.createSessionCalls, 0);
    expect(repository.sentClientMessageIds, isEmpty);
  });

  test('initial history error remains a full AsyncError without stale state',
      () async {
    final repository = _FakeAssistantRepository(
      sessions: <AssistantSessionEntity>[
        _session(
          id: 'active',
          locale: 'ru-KZ',
          title: '',
          lastMessageAt: DateTime.utc(2026, 9, 5),
        ),
      ],
      result: _result(),
      messageError: const AppException('assistant_network_error', 'raw'),
    );
    final container = ProviderContainer(overrides: <Override>[
      kundiAssistantEnabledProvider.overrideWithValue(true),
      assistantRepositoryProvider.overrideWithValue(repository),
      authControllerProvider.overrideWith(_FakeAuthController.new),
    ]);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    await expectLater(
      container.read(assistantControllerProvider.future),
      throwsA(isA<AppException>()),
    );
    expect(container.read(assistantControllerProvider).hasError, isTrue);
  });
}

Future<ProviderContainer> _container(
    _FakeAssistantRepository repository) async {
  final container = ProviderContainer(
    overrides: <Override>[
      kundiAssistantEnabledProvider.overrideWithValue(true),
      assistantRepositoryProvider.overrideWithValue(repository),
      authControllerProvider.overrideWith(_FakeAuthController.new),
    ],
  );
  await container.read(authControllerProvider.future);
  await container.read(assistantControllerProvider.future);
  return container;
}

class _FakeAuthController extends AuthController {
  static int buildCount = 0;

  @override
  Future<AuthSession?> build() async {
    buildCount++;
    return AuthSession(
      studentId: 'student',
      accessToken: 'token',
      refreshToken: 'refresh',
      expiresAt: DateTime.utc(2030),
    );
  }
}

class _FakeAssistantRepository implements AssistantRepository {
  _FakeAssistantRepository({
    required this.sessions,
    this.result,
    this.error,
    this.messages = const <AssistantMessageEntity>[],
    this.messageError,
  });

  final List<AssistantSessionEntity> sessions;
  final AssistantMessageResult? result;
  Object? error;
  List<AssistantMessageEntity> messages;
  Object? messageError;
  int listSessionCalls = 0;
  int listMessageCalls = 0;
  int createSessionCalls = 0;
  String lastClientMessageId = '';
  AssistantInputMode lastInputMode = AssistantInputMode.text;
  final List<String> sentClientMessageIds = <String>[];

  @override
  Future<AssistantSessionEntity> createSession(
      {required String accessToken}) async {
    createSessionCalls++;
    return sessions.first;
  }

  @override
  Future<void> deleteSession(
      {required String accessToken, required String sessionId}) async {}

  @override
  Future<AssistantPageResult<AssistantMessageEntity>> listMessages({
    required String accessToken,
    required String sessionId,
    String cursor = '',
    int limit = 20,
  }) async {
    listMessageCalls++;
    if (messageError != null) throw messageError!;
    return AssistantPageResult<AssistantMessageEntity>(items: messages);
  }

  @override
  Future<AssistantPageResult<AssistantSessionEntity>> listSessions({
    required String accessToken,
    String cursor = '',
    int limit = 20,
  }) async {
    listSessionCalls++;
    return AssistantPageResult<AssistantSessionEntity>(items: sessions);
  }

  @override
  Future<AssistantMessageResult> sendSessionMessage({
    required String accessToken,
    required String sessionId,
    required String clientMessageId,
    required String text,
    AssistantInputMode inputMode = AssistantInputMode.text,
  }) async {
    lastClientMessageId = clientMessageId;
    lastInputMode = inputMode;
    sentClientMessageIds.add(clientMessageId);
    if (error != null) throw error!;
    return result!;
  }

  @override
  Future<AssistantEntity> sendMessage({
    required String accessToken,
    required String text,
    required AssistantMode mode,
    required int gradeLevel,
    List<AssistantChatRecord> history = const <AssistantChatRecord>[],
  }) =>
      throw UnimplementedError();
}

AssistantMessageResult _result({AssistantSessionEntity? session}) {
  final now = DateTime.utc(2026, 9, 4, 12);
  return AssistantMessageResult(
    userMessage: _message('user', 'user', now),
    assistantMessage: _message('assistant', 'assistant', now),
    responseMode: 'explanation',
    helpLevel: 'guided',
    emotion: 'neutral',
    animationCue: 'standing',
    suggestions: const <String>[],
    session: session,
  );
}

AssistantMessageEntity _message(String id, String role, DateTime at) =>
    AssistantMessageEntity(
      id: id,
      sessionId: 'active',
      role: role,
      content: role == 'user' ? 'Вопрос' : 'Ответ',
      inputMode: 'text',
      responseMode: role == 'assistant' ? 'explanation' : '',
      createdAt: at,
    );

AssistantSessionEntity _session({
  required String id,
  required String locale,
  required String title,
  required DateTime lastMessageAt,
}) =>
    AssistantSessionEntity(
      id: id,
      locale: locale,
      gradeLevel: 7,
      title: title,
      createdAt: DateTime.utc(2026, 9, 4),
      updatedAt: lastMessageAt,
      lastMessageAt: lastMessageAt,
    );
