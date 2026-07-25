import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/kundi_behavior/domain/kundi_behavior_event.dart';
import 'package:kundi_mobile/features/kundi_behavior/domain/kundi_behavior_reducer.dart';
import 'package:kundi_mobile/features/kundi_behavior/domain/kundi_behavior_state.dart';

void main() {
  const reducer = KundiBehaviorReducer();
  final origin = DateTime.utc(2026, 7, 25, 10);

  KundiBehaviorEvent event(
    KundiBehaviorEventType type,
    String id, {
    Duration? duration,
    String? targetStateEventId,
  }) {
    return KundiBehaviorEvent(
      type: type,
      id: id,
      occurredAt: origin,
      duration: duration,
      targetStateEventId: targetStateEventId,
    );
  }

  test('neutral is the default state with explicit priority', () {
    final state = KundiBehaviorState.neutral(enteredAt: origin);

    expect(state.kind, KundiBehaviorKind.neutral);
    expect(state.priority, 0);
    expect(state.expiresAt, isNull);
  });

  test('higher priority preempts and lower priority is ignored', () {
    final neutral = KundiBehaviorState.neutral(enteredAt: origin);
    final celebration = reducer.reduce(
      neutral,
      event(KundiBehaviorEventType.homeworkCompleted, 'homework-1'),
    );
    final warning = reducer.reduce(
      celebration,
      event(KundiBehaviorEventType.absenceDetected, 'absence-1'),
    );
    final ignored = reducer.reduce(
      warning,
      event(KundiBehaviorEventType.allHomeworkCompleted, 'homework-all'),
    );

    expect(celebration.kind, KundiBehaviorKind.celebrating);
    expect(warning.kind, KundiBehaviorKind.warning);
    expect(identical(ignored, warning), isTrue);
  });

  test('equal priority replacement requires a new event id', () {
    final neutral = KundiBehaviorState.neutral(enteredAt: origin);
    final first = reducer.reduce(
      neutral,
      event(KundiBehaviorEventType.homeworkCompleted, 'event-1'),
    );
    final same = reducer.reduce(
      first,
      event(KundiBehaviorEventType.newGrade, 'event-1'),
    );
    final replacement = reducer.reduce(
      first,
      event(KundiBehaviorEventType.newGrade, 'event-2'),
    );

    expect(identical(same, first), isTrue);
    expect(replacement.sourceEventId, 'event-2');
    expect(replacement.kind, KundiBehaviorKind.celebrating);
  });

  test('warning and error are not displaced by celebration', () {
    final warning = reducer.reduce(
      KundiBehaviorState.neutral(enteredAt: origin),
      event(KundiBehaviorEventType.lowHomeworkProgress, 'warning-1'),
    );
    final error = reducer.reduce(
      warning,
      event(KundiBehaviorEventType.assistantFailure, 'error-1'),
    );

    expect(
      identical(
        reducer.reduce(
          warning,
          event(KundiBehaviorEventType.newGrade, 'grade-1'),
        ),
        warning,
      ),
      isTrue,
    );
    expect(
      identical(
        reducer.reduce(
          error,
          event(KundiBehaviorEventType.homeworkCompleted, 'homework-1'),
        ),
        error,
      ),
      isTrue,
    );
  });

  test('error preempts every behavior priority', () {
    for (final kind in KundiBehaviorKind.values) {
      final current = _stateForKind(kind, origin);
      final next = reducer.reduce(
        current,
        event(KundiBehaviorEventType.assistantFailure, 'error-${kind.name}'),
      );
      expect(next.kind, KundiBehaviorKind.error, reason: kind.name);
    }
  });

  test('user interruption ends only thinking speaking and listening', () {
    const interruptible = <KundiBehaviorKind>{
      KundiBehaviorKind.thinking,
      KundiBehaviorKind.speaking,
      KundiBehaviorKind.listening,
    };
    for (final kind in KundiBehaviorKind.values) {
      final current = _stateForKind(kind, origin);
      final next = reducer.reduce(
        current,
        event(KundiBehaviorEventType.userInterrupted, 'interrupt-${kind.name}'),
      );
      if (interruptible.contains(kind)) {
        expect(next.kind, KundiBehaviorKind.neutral, reason: kind.name);
      } else {
        expect(identical(next, current), isTrue, reason: kind.name);
      }
    }
  });

  test('timeout returns to neutral only for the current expired state', () {
    final celebration = reducer.reduce(
      KundiBehaviorState.neutral(enteredAt: origin),
      event(
        KundiBehaviorEventType.homeworkCompleted,
        'celebration-1',
        duration: const Duration(seconds: 3),
      ),
    );
    final beforeDeadline = reducer.reduce(
      celebration,
      KundiBehaviorEvent(
        type: KundiBehaviorEventType.timeoutElapsed,
        id: 'timeout-early',
        occurredAt: origin.add(const Duration(seconds: 2)),
        targetStateEventId: 'celebration-1',
      ),
    );
    final stale = reducer.reduce(
      celebration,
      KundiBehaviorEvent(
        type: KundiBehaviorEventType.timeoutElapsed,
        id: 'timeout-stale',
        occurredAt: origin.add(const Duration(seconds: 3)),
        targetStateEventId: 'older-event',
      ),
    );
    final expired = reducer.reduce(
      celebration,
      KundiBehaviorEvent(
        type: KundiBehaviorEventType.timeoutElapsed,
        id: 'timeout-current',
        occurredAt: origin.add(const Duration(seconds: 3)),
        targetStateEventId: 'celebration-1',
      ),
    );

    expect(identical(beforeDeadline, celebration), isTrue);
    expect(identical(stale, celebration), isTrue);
    expect(expired.kind, KundiBehaviorKind.neutral);
  });

  test('modeled-only events map to their Phase 1 behavior states', () {
    final expected = <KundiBehaviorEventType, KundiBehaviorKind>{
      KundiBehaviorEventType.homeworkCompleted: KundiBehaviorKind.celebrating,
      KundiBehaviorEventType.allHomeworkCompleted:
          KundiBehaviorKind.celebrating,
      KundiBehaviorEventType.newGrade: KundiBehaviorKind.celebrating,
      KundiBehaviorEventType.lowHomeworkProgress: KundiBehaviorKind.warning,
      KundiBehaviorEventType.absenceDetected: KundiBehaviorKind.warning,
      KundiBehaviorEventType.assistantQuestionSubmitted:
          KundiBehaviorKind.thinking,
      KundiBehaviorEventType.assistantResponseStarted:
          KundiBehaviorKind.thinking,
      KundiBehaviorEventType.assistantResponseReady: KundiBehaviorKind.speaking,
      KundiBehaviorEventType.audioPlaybackStarted: KundiBehaviorKind.speaking,
      KundiBehaviorEventType.assistantFailure: KundiBehaviorKind.error,
    };

    for (final entry in expected.entries) {
      final next = reducer.reduce(
        KundiBehaviorState.neutral(enteredAt: origin),
        event(entry.key, 'modeled-${entry.key.name}'),
      );
      expect(next.kind, entry.value, reason: entry.key.name);
    }
  });
}

KundiBehaviorState _stateForKind(
  KundiBehaviorKind kind,
  DateTime enteredAt,
) {
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
    sourceEventId: 'current-${kind.name}',
    presentationCue: cue,
  );
}
