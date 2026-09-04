enum KundiBehaviorEventType {
  appOpened,
  homeVisible,
  homeworkCompleted,
  allHomeworkCompleted,
  lowHomeworkProgress,
  newGrade,
  absenceDetected,
  assistantQuestionSubmitted,
  assistantListeningStarted,
  assistantResponseStarted,
  assistantResponseReady,
  audioPlaybackStarted,
  audioPlaybackFinished,
  assistantFailure,
  userInterrupted,
  dismissed,
  timeoutElapsed,
}

class KundiBehaviorEvent {
  const KundiBehaviorEvent({
    required this.type,
    required this.id,
    required this.occurredAt,
    this.fingerprint,
    this.duration,
    this.targetStateEventId,
  });

  final KundiBehaviorEventType type;
  final String id;
  final DateTime occurredAt;

  /// Opaque, non-PII identity used only for bounded in-memory deduplication.
  final String? fingerprint;
  final Duration? duration;

  /// Set by timeout events so an old callback cannot reset a newer state.
  final String? targetStateEventId;
}
