enum KundiBehaviorKind {
  neutral,
  celebrating,
  thinking,
  speaking,
  listening,
  warning,
  error,
}

extension KundiBehaviorKindPriority on KundiBehaviorKind {
  int get priority {
    switch (this) {
      case KundiBehaviorKind.neutral:
        return 0;
      case KundiBehaviorKind.celebrating:
        return 40;
      case KundiBehaviorKind.thinking:
        return 60;
      case KundiBehaviorKind.speaking:
        return 70;
      case KundiBehaviorKind.listening:
        return 80;
      case KundiBehaviorKind.warning:
        return 90;
      case KundiBehaviorKind.error:
        return 100;
    }
  }
}

enum KundiPresentationCue {
  neutral,
  celebrate,
  think,
  speak,
  listen,
  warn,
  error,
  unavailable,
}

class KundiBehaviorState {
  const KundiBehaviorState({
    required this.kind,
    required this.priority,
    required this.enteredAt,
    required this.sourceEventId,
    required this.presentationCue,
    this.expiresAt,
    this.fingerprint,
    this.safeMessageKey,
  });

  factory KundiBehaviorState.neutral({
    required DateTime enteredAt,
    String sourceEventId = 'initial',
    String? fingerprint,
  }) {
    return KundiBehaviorState(
      kind: KundiBehaviorKind.neutral,
      priority: KundiBehaviorKind.neutral.priority,
      enteredAt: enteredAt,
      sourceEventId: sourceEventId,
      fingerprint: fingerprint,
      presentationCue: KundiPresentationCue.neutral,
      safeMessageKey: 'kundi.neutral',
    );
  }

  final KundiBehaviorKind kind;
  final int priority;
  final DateTime enteredAt;
  final DateTime? expiresAt;
  final String sourceEventId;
  final String? fingerprint;
  final KundiPresentationCue presentationCue;
  final String? safeMessageKey;
}
