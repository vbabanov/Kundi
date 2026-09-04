import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/assistant/application/assistant_controller.dart';
import 'package:kundi_mobile/features/assistant/domain/assistant_entity.dart';
import 'package:kundi_mobile/features/assistant/presentation/assistant_page.dart';

void main() {
  testWidgets(
      'renders text-only conversation without microphone or provider data',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
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
}

AssistantViewState _viewState({
  bool isSending = false,
  String pendingText = '',
  String errorMessage = 'Не удалось отправить сообщение.',
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
    retryText: errorMessage.isEmpty ? '' : 'Повтори вопрос',
    retryClientMessageId: errorMessage.isEmpty ? '' : 'client-1',
  );
}

class _FakeAssistantController extends AssistantController {
  _FakeAssistantController(this.initial);
  final AssistantViewState initial;

  @override
  Future<AssistantViewState> build() async => initial;

  @override
  Future<void> retryLastMessage() async {}
}
