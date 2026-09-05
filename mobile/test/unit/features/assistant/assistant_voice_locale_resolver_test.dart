import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/assistant/application/assistant_controller.dart';
import 'package:kundi_mobile/features/assistant/application/assistant_voice_locale_resolver.dart';
import 'package:kundi_mobile/features/assistant/domain/assistant_entity.dart';

void main() {
  test('active kk-KZ session wins without waiting for initialization',
      () async {
    var waits = 0;
    final resolver = AssistantVoiceLocaleResolver(
      activeSessionLocale: () => 'kk-KZ',
      waitForAssistant: () async {
        waits++;
        return _view('ru-KZ');
      },
    );

    final result = await resolver.resolve();

    expect(result.locale, 'kk-KZ');
    expect(result.source, AssistantVoiceLocaleSource.activeSession);
    expect(waits, 0);
  });

  test('active ru-KZ session remains the application locale', () async {
    final resolver = AssistantVoiceLocaleResolver(
      activeSessionLocale: () => 'ru-KZ',
      waitForAssistant: () async => _view('kk-KZ'),
    );

    expect((await resolver.resolve()).locale, 'ru-KZ');
  });

  test('missing session waits for the one canonical kk-KZ session', () async {
    final ready = Completer<AssistantViewState>();
    var waits = 0;
    final resolver = AssistantVoiceLocaleResolver(
      activeSessionLocale: () => null,
      waitForAssistant: () {
        waits++;
        return ready.future;
      },
    );

    final first = resolver.resolve();
    final second = resolver.resolve();
    var completed = false;
    first.then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect(waits, 1);

    ready.complete(_view('kk-KZ'));
    expect((await first).locale, 'kk-KZ');
    expect((await second).locale, 'kk-KZ');
    expect(waits, 1);
  });

  test('missing session resolves canonical ru-KZ session', () async {
    final resolver = AssistantVoiceLocaleResolver(
      activeSessionLocale: () => null,
      waitForAssistant: () async => _view('ru-KZ'),
    );

    final result = await resolver.resolve();
    expect(result.locale, 'ru-KZ');
    expect(result.source, AssistantVoiceLocaleSource.ensuredSession);
  });

  test('controller error and empty locale use documented fallback', () async {
    final failing = AssistantVoiceLocaleResolver(
      activeSessionLocale: () => null,
      waitForAssistant: () => Future<AssistantViewState>.error('offline'),
    );
    final empty = AssistantVoiceLocaleResolver(
      activeSessionLocale: () => null,
      waitForAssistant: () async => const AssistantViewState(),
    );

    expect((await failing.resolve()).locale, 'ru-KZ');
    expect(
      (await failing.resolve()).source,
      AssistantVoiceLocaleSource.fallback,
    );
    expect((await empty.resolve()).locale, 'ru-KZ');
  });

  test('active session has documented priority over ensured mismatch',
      () async {
    var active = 'kk-KZ';
    final resolver = AssistantVoiceLocaleResolver(
      activeSessionLocale: () => active,
      waitForAssistant: () async => _view('ru-KZ'),
    );

    expect((await resolver.resolve()).locale, 'kk-KZ');
    active = 'ru-KZ';
    expect((await resolver.resolve()).locale, 'ru-KZ');
  });
}

AssistantViewState _view(String locale) {
  final now = DateTime.utc(2026, 9, 5);
  return AssistantViewState(
    activeSession: AssistantSessionEntity(
      id: 'session',
      locale: locale,
      gradeLevel: 7,
      title: '',
      createdAt: now,
      updatedAt: now,
      lastMessageAt: now,
    ),
  );
}
