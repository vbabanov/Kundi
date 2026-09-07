import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/kundi_behavior/domain/kundi_behavior_state.dart';
import 'package:kundi_mobile/features/kundi_behavior/presentation/kundi_home_presentation_adapter.dart';
import 'package:kundi_mobile/runtimes/kundi_native_avatar/kundi_native_avatar_protocol.dart';

void main() {
  const adapter = KundiHomePresentationAdapter();
  final now = DateTime.utc(2026, 7, 25, 10);

  test('every state uses the safe WebP fallback and renderer-neutral cue', () {
    for (final kind in KundiBehaviorKind.values) {
      final presentation = adapter.adapt(
        state: _state(kind, now),
        neutralTitle: 'Доброе утро, Артем',
        neutralMessage: 'План на сегодня.',
        neutralSemanticLabel: 'План доступен',
      );

      expect(
        presentation.assetPath,
        'assets/images/kundi/home/kundi_home.webp',
        reason: kind.name,
      );
      expect(presentation.title, 'Доброе утро, Артем', reason: kind.name);
      expect(presentation.message.trim(), isNotEmpty, reason: kind.name);
      expect(
        presentation.animationCueName,
        isNot(contains(RegExp(r'Unity|Filament|MethodChannel'))),
      );
    }
  });

  test('neutral keeps the existing contextual Home copy', () {
    final presentation = adapter.adapt(
      state: KundiBehaviorState.neutral(enteredAt: now),
      neutralTitle: 'Добрый день',
      neutralMessage: 'Текущий контекст Главной',
      neutralSemanticLabel: 'Текущая семантика',
    );

    expect(presentation.title, 'Добрый день');
    expect(presentation.message, 'Текущий контекст Главной');
    expect(presentation.semanticLabel, 'Текущая семантика');
    expect(presentation.visualEmphasis, KundiVisualEmphasis.none);
  });

  test('unavailable or mismatched cue safely falls back to neutral', () {
    final invalid = KundiBehaviorState(
      kind: KundiBehaviorKind.warning,
      priority: KundiBehaviorKind.warning.priority,
      enteredAt: now,
      sourceEventId: 'warning-1',
      presentationCue: KundiPresentationCue.unavailable,
    );
    final presentation = adapter.adapt(
      state: invalid,
      neutralTitle: 'Привет',
      neutralMessage: 'Безопасный fallback',
      neutralSemanticLabel: 'Нейтральное состояние',
    );

    expect(presentation.message, 'Безопасный fallback');
    expect(presentation.animationCueName, 'neutral');
    expect(presentation.visualEmphasis, KundiVisualEmphasis.none);
  });

  test('warning and error copy is neutral and non-accusatory', () {
    final messages = <String>[
      adapter
          .adapt(
            state: _state(KundiBehaviorKind.warning, now),
            neutralTitle: 'Привет',
            neutralMessage: 'План',
            neutralSemanticLabel: 'План',
          )
          .message,
      adapter
          .adapt(
            state: _state(KundiBehaviorKind.error, now),
            neutralTitle: 'Привет',
            neutralMessage: 'План',
            neutralSemanticLabel: 'План',
          )
          .message,
    ];

    for (final message in messages) {
      expect(message, isNot(contains(RegExp(r'виноват|плохо|опасно'))));
      expect(message, isNot(contains(RegExp(r'Рµ|Р°|СЃ|вЂ'))));
    }
  });

  test(
      'behavior states map to bounded soft expressions and never auto-use Angry',
      () {
    final expected = <KundiBehaviorKind, (KundiNativeAvatarEmotion, double)>{
      KundiBehaviorKind.neutral: (KundiNativeAvatarEmotion.neutral, 1),
      KundiBehaviorKind.celebrating: (KundiNativeAvatarEmotion.joy, 0.52),
      KundiBehaviorKind.thinking: (KundiNativeAvatarEmotion.surprised, 0.18),
      KundiBehaviorKind.speaking: (KundiNativeAvatarEmotion.joy, 0.14),
      KundiBehaviorKind.listening: (KundiNativeAvatarEmotion.joy, 0.16),
      KundiBehaviorKind.warning: (KundiNativeAvatarEmotion.sorrow, 0.22),
      KundiBehaviorKind.error: (KundiNativeAvatarEmotion.sorrow, 0.32),
    };

    for (final entry in expected.entries) {
      final expression = adapter
          .adapt(
            state: _state(entry.key, now),
            neutralTitle: 'Kundi',
            neutralMessage: 'План',
            neutralSemanticLabel: 'План',
          )
          .facialExpression;
      expect(expression.emotion, entry.value.$1, reason: entry.key.name);
      expect(expression.intensity, entry.value.$2, reason: entry.key.name);
      expect(expression.intensity, inInclusiveRange(0, 1));
      expect(expression.emotion, isNot(KundiNativeAvatarEmotion.angry));
    }
  });
}

KundiBehaviorState _state(KundiBehaviorKind kind, DateTime enteredAt) {
  final cue = switch (kind) {
    KundiBehaviorKind.neutral => KundiPresentationCue.neutral,
    KundiBehaviorKind.celebrating => KundiPresentationCue.celebrate,
    KundiBehaviorKind.thinking => KundiPresentationCue.think,
    KundiBehaviorKind.speaking => KundiPresentationCue.speak,
    KundiBehaviorKind.listening => KundiPresentationCue.listen,
    KundiBehaviorKind.warning => KundiPresentationCue.warn,
    KundiBehaviorKind.error => KundiPresentationCue.error,
  };
  return KundiBehaviorState(
    kind: kind,
    priority: kind.priority,
    enteredAt: enteredAt,
    sourceEventId: 'state-${kind.name}',
    presentationCue: cue,
  );
}
