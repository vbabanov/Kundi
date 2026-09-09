import 'kundi_behavior_event.dart';
import 'kundi_behavior_state.dart';

class KundiBehaviorReducer {
  const KundiBehaviorReducer();

  KundiBehaviorState reduce(
    KundiBehaviorState current,
    KundiBehaviorEvent event,
  ) {
    switch (event.type) {
      case KundiBehaviorEventType.userInterrupted:
        return _interrupt(current, event);
      case KundiBehaviorEventType.dismissed:
        return current.kind == KundiBehaviorKind.neutral
            ? current
            : _neutralFrom(event);
      case KundiBehaviorEventType.timeoutElapsed:
        return _timeout(current, event);
      case KundiBehaviorEventType.audioPlaybackFinished:
        return current.kind == KundiBehaviorKind.speaking
            ? _neutralFrom(event)
            : current;
      case KundiBehaviorEventType.appOpened:
      case KundiBehaviorEventType.homeVisible:
      case KundiBehaviorEventType.homeworkCompleted:
      case KundiBehaviorEventType.allHomeworkCompleted:
      case KundiBehaviorEventType.lowHomeworkProgress:
      case KundiBehaviorEventType.newGrade:
      case KundiBehaviorEventType.achievementUnlocked:
      case KundiBehaviorEventType.absenceDetected:
      case KundiBehaviorEventType.assistantQuestionSubmitted:
      case KundiBehaviorEventType.assistantListeningStarted:
      case KundiBehaviorEventType.assistantResponseStarted:
      case KundiBehaviorEventType.assistantResponseReady:
      case KundiBehaviorEventType.audioPlaybackStarted:
      case KundiBehaviorEventType.assistantFailure:
        return _applyPriority(current, _stateFor(event));
    }
  }

  KundiBehaviorState _applyPriority(
    KundiBehaviorState current,
    KundiBehaviorState candidate,
  ) {
    if (candidate.priority < current.priority) {
      return current;
    }
    if (candidate.priority == current.priority &&
        candidate.sourceEventId == current.sourceEventId) {
      return current;
    }
    return candidate;
  }

  KundiBehaviorState _interrupt(
    KundiBehaviorState current,
    KundiBehaviorEvent event,
  ) {
    const interruptible = <KundiBehaviorKind>{
      KundiBehaviorKind.listening,
      KundiBehaviorKind.thinking,
      KundiBehaviorKind.speaking,
    };
    return interruptible.contains(current.kind) ? _neutralFrom(event) : current;
  }

  KundiBehaviorState _timeout(
    KundiBehaviorState current,
    KundiBehaviorEvent event,
  ) {
    if (event.targetStateEventId != current.sourceEventId) {
      return current;
    }
    final deadline = current.expiresAt;
    if (deadline == null || event.occurredAt.isBefore(deadline)) {
      return current;
    }
    return _neutralFrom(event);
  }

  KundiBehaviorState _stateFor(KundiBehaviorEvent event) {
    final kind = _kindFor(event.type);
    final duration = event.duration ?? _defaultDuration(kind);
    return KundiBehaviorState(
      kind: kind,
      priority: kind.priority,
      enteredAt: event.occurredAt,
      expiresAt: duration == null ? null : event.occurredAt.add(duration),
      sourceEventId: event.id,
      fingerprint: event.fingerprint,
      presentationCue: _cueFor(kind),
      safeMessageKey: _messageKeyFor(kind),
    );
  }

  KundiBehaviorState _neutralFrom(KundiBehaviorEvent event) {
    return KundiBehaviorState.neutral(
      enteredAt: event.occurredAt,
      sourceEventId: event.id,
      fingerprint: event.fingerprint,
    );
  }

  KundiBehaviorKind _kindFor(KundiBehaviorEventType type) {
    switch (type) {
      case KundiBehaviorEventType.appOpened:
      case KundiBehaviorEventType.homeVisible:
      case KundiBehaviorEventType.audioPlaybackFinished:
      case KundiBehaviorEventType.userInterrupted:
      case KundiBehaviorEventType.dismissed:
      case KundiBehaviorEventType.timeoutElapsed:
        return KundiBehaviorKind.neutral;
      case KundiBehaviorEventType.homeworkCompleted:
      case KundiBehaviorEventType.allHomeworkCompleted:
      case KundiBehaviorEventType.newGrade:
      case KundiBehaviorEventType.achievementUnlocked:
        return KundiBehaviorKind.celebrating;
      case KundiBehaviorEventType.assistantQuestionSubmitted:
      case KundiBehaviorEventType.assistantResponseStarted:
        return KundiBehaviorKind.thinking;
      case KundiBehaviorEventType.assistantListeningStarted:
        return KundiBehaviorKind.listening;
      case KundiBehaviorEventType.assistantResponseReady:
      case KundiBehaviorEventType.audioPlaybackStarted:
        return KundiBehaviorKind.speaking;
      case KundiBehaviorEventType.lowHomeworkProgress:
      case KundiBehaviorEventType.absenceDetected:
        return KundiBehaviorKind.warning;
      case KundiBehaviorEventType.assistantFailure:
        return KundiBehaviorKind.error;
    }
  }

  Duration? _defaultDuration(KundiBehaviorKind kind) {
    switch (kind) {
      case KundiBehaviorKind.neutral:
        return null;
      case KundiBehaviorKind.celebrating:
        return const Duration(seconds: 3);
      case KundiBehaviorKind.thinking:
        return const Duration(seconds: 30);
      case KundiBehaviorKind.speaking:
        return const Duration(seconds: 8);
      case KundiBehaviorKind.listening:
        return const Duration(seconds: 30);
      case KundiBehaviorKind.warning:
        return const Duration(seconds: 6);
      case KundiBehaviorKind.error:
        return const Duration(seconds: 8);
    }
  }

  KundiPresentationCue _cueFor(KundiBehaviorKind kind) {
    switch (kind) {
      case KundiBehaviorKind.neutral:
        return KundiPresentationCue.neutral;
      case KundiBehaviorKind.celebrating:
        return KundiPresentationCue.celebrate;
      case KundiBehaviorKind.thinking:
        return KundiPresentationCue.think;
      case KundiBehaviorKind.speaking:
        return KundiPresentationCue.speak;
      case KundiBehaviorKind.listening:
        return KundiPresentationCue.listen;
      case KundiBehaviorKind.warning:
        return KundiPresentationCue.warn;
      case KundiBehaviorKind.error:
        return KundiPresentationCue.error;
    }
  }

  String _messageKeyFor(KundiBehaviorKind kind) => 'kundi.${kind.name}';
}
