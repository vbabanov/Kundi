import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/assistant/application/assistant_controller.dart';
import 'package:kundi_mobile/features/assistant/assistant_feature.dart';
import 'package:kundi_mobile/features/assistant/domain/assistant_entity.dart';
import 'package:kundi_mobile/features/assistant/domain/assistant_repository.dart';
import 'package:kundi_mobile/features/assistant/presentation/assistant_page.dart';
import 'package:kundi_mobile/features/auth/application/auth_controller.dart';
import 'package:kundi_mobile/features/auth/domain/auth_session.dart';
import 'package:kundi_mobile/l10n/generated/app_localizations.dart';
import 'package:kundi_mobile/shared/theme/app_theme.dart';
import 'package:kundi_mobile/shared/theme/kundi_tokens.dart';

void main() {
  for (final theme in <ThemeData>[AppTheme.light, AppTheme.dark]) {
    for (final locale in const <Locale>[Locale('ru'), Locale('kk')]) {
      testWidgets(
        'assistant chrome and composer fit ${theme.brightness} ${locale.languageCode}',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 640));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final view = _viewState(errorMessage: '').copyWith(
            suggestions: const <String>[
              'Объясни тему очень простыми словами и с примером',
              'Проверь мой ответ',
              'Помоги сделать первый шаг',
            ],
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                assistantControllerProvider.overrideWith(
                  () => _FakeAssistantController(view),
                ),
              ],
              child: MaterialApp(
                theme: theme,
                locale: locale,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                home: const AssistantPage(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('assistant-top-bar')), findsOneWidget);
          expect(
            find.text(locale.languageCode == 'kk'
                ? 'Kundi-ден сұраңыз'
                : 'Спросите Kundi'),
            findsOneWidget,
          );
          expect(
            find.text(locale.languageCode == 'kk'
                ? 'Оқу бойынша көмекші'
                : 'Помощник по учёбе'),
            findsOneWidget,
          );
          final suggestion = tester.widget<ActionChip>(
            find.byKey(const Key('assistant-suggestion-0')),
          );
          final suggestionLabel = suggestion.label as Text;
          final suggestionIcon = suggestion.avatar as Icon;
          expect(suggestion.backgroundColor, theme.colorScheme.kundiElevated);
          expect(suggestionLabel.style?.color, theme.colorScheme.onSurface);
          expect(suggestionIcon.color, theme.colorScheme.primary);
          final send = tester.widget<IconButton>(
            find.byKey(const Key('assistant-send-button')),
          );
          expect(send.onPressed, isNull);
          await tester.tap(find.byKey(const Key('assistant-suggestion-0')));
          await tester.pump();
          expect(
            tester
                .widget<IconButton>(
                  find.byKey(const Key('assistant-send-button')),
                )
                .onPressed,
            isNotNull,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('composer stays above the reported keyboard inset',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assistantControllerProvider.overrideWith(
            () => _FakeAssistantController(_viewState(errorMessage: '')),
          ),
        ],
        child: const MaterialApp(home: AssistantPage()),
      ),
    );
    await tester.pumpAndSettle();

    final initialBottom = tester.getBottomRight(
      find.byKey(const Key('assistant-text-field')),
    );
    tester.view.viewInsets =
        FakeViewPadding(bottom: 240 * tester.view.devicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final keyboardBottom = tester.getBottomRight(
      find.byKey(const Key('assistant-text-field')),
    );

    expect(initialBottom.dy - keyboardBottom.dy, closeTo(240, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('prepares the legacy Android layout before suggestion focus',
      (tester) async {
    const channel = MethodChannel(
      'com.kundi.kundi_mobile/legacy_ime_layout',
    );
    var prepareCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        if (call.method == 'prepareForIme') prepareCalls++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assistantControllerProvider.overrideWith(
            () => _FakeAssistantController(_viewState(errorMessage: '')),
          ),
        ],
        child: const MaterialApp(home: AssistantPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('assistant-suggestion-0')));
    await tester.pumpAndSettle();

    expect(prepareCalls, greaterThanOrEqualTo(1));
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('assistant-text-field')),
          )
          .focusNode
          ?.hasFocus,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'renders text-only conversation without microphone or provider data',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          assistantControllerProvider.overrideWith(
            () => _FakeAssistantController(_viewState()),
          ),
        ],
        child: const MaterialApp(home: AssistantPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Спросите Kundi'), findsOneWidget);
    expect(find.textContaining('Ұзақ мәтін'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsNothing);
    expect(find.textContaining('provider'), findsNothing);
    expect(find.byKey(const Key('assistant-text-field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows thinking state and retry transport failure',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          assistantControllerProvider.overrideWith(
            () => _FakeAssistantController(_viewState(
              isSending: true,
              pendingText: 'Объясни дроби',
              errorMessage: '',
            )),
          ),
        ],
        child: const MaterialApp(home: AssistantPage()),
      ),
    );
    await tester.pump();
    expect(find.text('Kundi думает…'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsNothing);
  });

  testWidgets('marks persisted voice messages in the shared history',
      (tester) async {
    final view = _viewState();
    final now = DateTime.utc(2026, 9, 4, 12);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assistantControllerProvider.overrideWith(
            () => _FakeAssistantController(view.copyWith(messages: [
              AssistantMessageEntity(
                id: 'voice-1',
                sessionId: 'session-1',
                role: 'user',
                content: 'Объясни дроби',
                inputMode: 'voice',
                responseMode: '',
                createdAt: now,
              ),
            ])),
          ),
        ],
        child: const MaterialApp(home: AssistantPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('assistant-voice-message-badge')), findsOneWidget);
    expect(find.text('Голосом'), findsOneWidget);
  });

  testWidgets('shows retry only for retryable send failures', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          assistantControllerProvider.overrideWith(
            () => _FakeAssistantController(_viewState(
              errorMessage: 'Kundi временно не смогла ответить.',
              retryable: true,
            )),
          ),
        ],
        child: const MaterialApp(home: AssistantPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kundi временно не смогла ответить.'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
    final transportError = tester.widget<Container>(
      find.byKey(const Key('assistant-transport-error')),
    );
    final decoration = transportError.decoration! as BoxDecoration;
    expect(
        decoration.color,
        isNot(Theme.of(tester.element(find.byType(AssistantPage)))
            .colorScheme
            .errorContainer));
    expect(decoration.border, isNotNull);

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          assistantControllerProvider.overrideWith(
            () => _FakeAssistantController(_viewState(
              errorMessage: 'Kundi пока недоступна.',
              retryable: false,
            )),
          ),
        ],
        child: const MaterialApp(home: AssistantPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kundi пока недоступна.'), findsOneWidget);
    expect(find.text('Повторить'), findsNothing);
  });

  testWidgets('refresh failure banner keeps the loaded conversation visible',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assistantControllerProvider.overrideWith(
            () => _FakeAssistantController(_viewState(
              errorMessage: '',
            ).copyWith(
              refreshErrorMessage: 'Не удалось обновить историю',
            )),
          ),
        ],
        child: const MaterialApp(home: AssistantPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Ұзақ мәтін'), findsOneWidget);
    expect(find.text('Не удалось обновить историю'), findsOneWidget);
    expect(find.text('Не удалось загрузить диалог.'), findsNothing);
    expect(find.text('Повторить'), findsOneWidget);
  });

  testWidgets('initial load error uses the full retry state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assistantControllerProvider.overrideWith(
            _FailingAssistantController.new,
          ),
        ],
        child: const MaterialApp(home: AssistantPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Не удалось загрузить диалог.'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
    expect(find.byKey(const Key('assistant-message-list')), findsNothing);
  });

  testWidgets(
      'route re-entry and rebuild retain history without duplicate requests',
      (tester) async {
    final counters = _AssistantLifecycleCounters();
    final repository = _CountingAssistantRepository(counters);
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kundiAssistantEnabledProvider.overrideWithValue(true),
          assistantRepositoryProvider.overrideWithValue(repository),
          authControllerProvider.overrideWith(_CountingAuthController.new),
          assistantControllerProvider.overrideWith(() {
            counters.assistantControllerCreateCount++;
            return _CountingAssistantController(counters);
          }),
        ],
        child: MaterialApp(home: _AssistantRouteHost(counters: counters)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-assistant')));
    await tester.pumpAndSettle();
    expect(find.text('Сохранённое сообщение'), findsOneWidget);
    expect(counters.assistantPageOpenCount, 1);
    expect(counters.assistantControllerCreateCount, 1);
    expect(counters.assistantControllerBuildCount, 1);
    expect(counters.listSessionsRequestCount, 1);
    expect(counters.listMessagesRequestCount, 1);
    expect(counters.createSessionRequestCount, 0);
    expect(counters.sendMessageRequestCount, 0);

    await tester.binding.setSurfaceSize(const Size(400, 760));
    await tester.pump();
    await tester.binding.setSurfaceSize(const Size(390, 760));
    await tester.pump();
    expect(counters.assistantControllerBuildCount, 1);
    expect(counters.listMessagesRequestCount, 1);

    await tester.tap(find.byKey(const Key('assistant-history-button')));
    await tester.pumpAndSettle();
    expect(find.text('Прошлые диалоги'), findsOneWidget);
    expect(counters.listMessagesRequestCount, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(counters.assistantControllerDisposeCount, 0);
    await tester.tap(find.byKey(const Key('open-assistant')));
    await tester.pumpAndSettle();

    expect(find.text('Сохранённое сообщение'), findsOneWidget);
    expect(counters.assistantPageOpenCount, 2);
    expect(counters.assistantControllerCreateCount, 1);
    expect(counters.assistantControllerBuildCount, 1);
    expect(counters.assistantControllerDisposeCount, 0);
    expect(counters.listSessionsRequestCount, 1);
    expect(counters.listMessagesRequestCount, 2);
    expect(counters.explicitRefreshCount, 0);
    expect(counters.createSessionRequestCount, 0);
    expect(counters.sendMessageRequestCount, 0);
  });
}

AssistantViewState _viewState({
  bool isSending = false,
  String pendingText = '',
  String errorMessage = 'Не удалось отправить сообщение.',
  bool retryable = true,
}) {
  final now = DateTime.utc(2026, 9, 4);
  return AssistantViewState(
    activeSession: AssistantSessionEntity(
      id: 'session-1',
      locale: 'kk-KZ',
      gradeLevel: 8,
      title: 'Дроби',
      createdAt: now,
      updatedAt: now,
      lastMessageAt: now,
    ),
    messages: [
      AssistantMessageEntity(
        id: 'message-1',
        sessionId: 'session-1',
        role: 'assistant',
        content:
            'Ұзақ мәтін экраннан шықпайды: бөлшектерді қадам бойынша түсіндіремін. '
            'Русский текст также переносится и остаётся читаемым.',
        inputMode: 'text',
        responseMode: 'explanation',
        createdAt: now,
      ),
    ],
    suggestions: const ['Объясни тему', 'Проверь мой ответ'],
    isSending: isSending,
    pendingText: pendingText,
    errorMessage: errorMessage,
    retryText: errorMessage.isEmpty || !retryable ? '' : 'Повтори вопрос',
    retryClientMessageId: errorMessage.isEmpty || !retryable ? '' : 'client-1',
  );
}

class _FakeAssistantController extends AssistantController {
  _FakeAssistantController(this.initial);
  final AssistantViewState initial;

  @override
  Future<AssistantViewState> build() async => initial;

  @override
  Future<void> retryLastMessage() async {}

  @override
  Future<void> revalidateOnPageOpen() async {}
}

class _FailingAssistantController extends AssistantController {
  @override
  Future<AssistantViewState> build() =>
      Future<AssistantViewState>.error(StateError('offline'));

  @override
  Future<void> revalidateOnPageOpen() async {}
}

class _AssistantLifecycleCounters {
  int assistantControllerCreateCount = 0;
  int assistantControllerBuildCount = 0;
  int assistantControllerDisposeCount = 0;
  int assistantPageOpenCount = 0;
  int listSessionsRequestCount = 0;
  int listMessagesRequestCount = 0;
  int createSessionRequestCount = 0;
  int sendMessageRequestCount = 0;
  int explicitRefreshCount = 0;
}

class _CountingAssistantController extends AssistantController {
  _CountingAssistantController(this.counters);

  final _AssistantLifecycleCounters counters;

  @override
  Future<AssistantViewState> build() {
    counters.assistantControllerBuildCount++;
    ref.onDispose(() => counters.assistantControllerDisposeCount++);
    return super.build();
  }
}

class _CountingAuthController extends AuthController {
  @override
  Future<AuthSession?> build() async => AuthSession(
        studentId: 'student',
        accessToken: 'token',
        refreshToken: 'refresh',
        expiresAt: DateTime.utc(2030),
      );
}

class _AssistantRouteHost extends ConsumerWidget {
  const _AssistantRouteHost({required this.counters});

  final _AssistantLifecycleCounters counters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authReady = ref.watch(authControllerProvider).hasValue;
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const Key('open-assistant'),
          onPressed: authReady
              ? () {
                  counters.assistantPageOpenCount++;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AssistantPage(),
                    ),
                  );
                }
              : null,
          child: const Text('Открыть Kundi'),
        ),
      ),
    );
  }
}

class _CountingAssistantRepository implements AssistantRepository {
  _CountingAssistantRepository(this.counters);

  final _AssistantLifecycleCounters counters;

  AssistantSessionEntity get _session => AssistantSessionEntity(
        id: 'session-1',
        locale: 'ru-KZ',
        gradeLevel: 7,
        title: 'Сохранённый диалог',
        createdAt: DateTime.utc(2026, 9, 4),
        updatedAt: DateTime.utc(2026, 9, 4),
        lastMessageAt: DateTime.utc(2026, 9, 4),
      );

  @override
  Future<AssistantSessionEntity> createSession({
    required String accessToken,
  }) async {
    counters.createSessionRequestCount++;
    return _session;
  }

  @override
  Future<void> deleteSession({
    required String accessToken,
    required String sessionId,
  }) async {}

  @override
  Future<AssistantPageResult<AssistantMessageEntity>> listMessages({
    required String accessToken,
    required String sessionId,
    String cursor = '',
    int limit = 20,
  }) async {
    counters.listMessagesRequestCount++;
    return AssistantPageResult<AssistantMessageEntity>(
      items: [
        AssistantMessageEntity(
          id: 'message-1',
          sessionId: sessionId,
          role: 'assistant',
          content: 'Сохранённое сообщение',
          inputMode: 'text',
          responseMode: 'explanation',
          createdAt: DateTime.utc(2026, 9, 4),
        ),
      ],
    );
  }

  @override
  Future<AssistantPageResult<AssistantSessionEntity>> listSessions({
    required String accessToken,
    String cursor = '',
    int limit = 20,
  }) async {
    counters.listSessionsRequestCount++;
    return AssistantPageResult<AssistantSessionEntity>(items: [_session]);
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

  @override
  Future<AssistantMessageResult> sendSessionMessage({
    required String accessToken,
    required String sessionId,
    required String clientMessageId,
    required String text,
    AssistantInputMode inputMode = AssistantInputMode.text,
  }) async {
    counters.sendMessageRequestCount++;
    throw UnimplementedError();
  }
}
