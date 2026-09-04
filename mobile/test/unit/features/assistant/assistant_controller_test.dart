import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/errors/app_exception.dart';
import 'package:kundi_mobile/features/assistant/application/assistant_controller.dart';
import 'package:kundi_mobile/features/assistant/assistant_feature.dart';
import 'package:kundi_mobile/features/assistant/domain/assistant_entity.dart';
import 'package:kundi_mobile/features/assistant/domain/assistant_repository.dart';
import 'package:kundi_mobile/features/auth/application/auth_controller.dart';
import 'package:kundi_mobile/features/auth/domain/auth_session.dart';

void main() {
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
    expect(state.suggestions.first, 'Тақырыпты түсіндір');
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
    await controller.sendMessage('Вопрос');
    final originalID = repository.lastClientMessageId;
    repository.error = null;
    await controller.retryLastMessage();
    expect(repository.sentClientMessageIds, <String>[originalID, originalID]);
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
  });

  final List<AssistantSessionEntity> sessions;
  final AssistantMessageResult? result;
  Object? error;
  int listSessionCalls = 0;
  String lastClientMessageId = '';
  final List<String> sentClientMessageIds = <String>[];

  @override
  Future<AssistantSessionEntity> createSession(
          {required String accessToken}) async =>
      sessions.first;

  @override
  Future<void> deleteSession(
      {required String accessToken, required String sessionId}) async {}

  @override
  Future<AssistantPageResult<AssistantMessageEntity>> listMessages({
    required String accessToken,
    required String sessionId,
    String cursor = '',
    int limit = 20,
  }) async =>
      const AssistantPageResult<AssistantMessageEntity>(
          items: <AssistantMessageEntity>[]);

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
  }) async {
    lastClientMessageId = clientMessageId;
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
