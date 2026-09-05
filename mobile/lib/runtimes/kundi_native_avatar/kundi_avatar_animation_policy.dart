import 'package:flutter/foundation.dart';

enum KundiAvatarAnimationTarget {
  standing,
  idle,
  talking,
  waiting,
  dansing,
}

@immutable
final class KundiAvatarAnimationDecision {
  const KundiAvatarAnimationDecision(
    this.target, {
    this.talkingVariant,
  });

  final KundiAvatarAnimationTarget target;
  final int? talkingVariant;
}

/// Renderer-neutral mapping between product cues and the GLB animation set.
abstract final class KundiAvatarAnimationPolicy {
  /// GLB quaternion audit (camera at +Z) found only Talking2 keeps the Home
  /// torso frontal: hips/chest stay within about 3 degrees of the camera.
  /// Talking and Talking3 carry persistent positive torso/head yaw and remain
  /// available in the asset for a future fullscreen animation pass.
  static const Set<int> frontalTalkingVariants = <int>{2};

  static KundiAvatarAnimationDecision resolve({
    required String cueName,
    required String identity,
  }) {
    switch (cueName) {
      case 'listen':
        return const KundiAvatarAnimationDecision(
          KundiAvatarAnimationTarget.idle,
        );
      case 'speak':
        return KundiAvatarAnimationDecision(
          KundiAvatarAnimationTarget.talking,
          talkingVariant: talkingVariant(identity),
        );
      case 'think':
      case 'warn':
      case 'error':
        return const KundiAvatarAnimationDecision(
          KundiAvatarAnimationTarget.waiting,
        );
      case 'celebrate':
        return const KundiAvatarAnimationDecision(
          KundiAvatarAnimationTarget.dansing,
        );
      default:
        return const KundiAvatarAnimationDecision(
          KundiAvatarAnimationTarget.standing,
        );
    }
  }

  static int talkingVariant(String identity) {
    final hash = identity.codeUnits.fold<int>(0, (sum, value) => sum + value);
    final variants = frontalTalkingVariants.toList(growable: false)..sort();
    return variants[hash % variants.length];
  }
}

enum KundiAvatarLongWaitAction { waiting, dansing, standing }

/// Future-facing policy only. It is intentionally not wired to Home or AI/TTS.
final class KundiAvatarLongWaitPolicy {
  KundiAvatarLongWaitPolicy({
    this.entertainmentThreshold = const Duration(seconds: 6),
  });

  final Duration entertainmentThreshold;
  bool _danceIssued = false;
  bool _cancelled = false;

  KundiAvatarLongWaitAction actionFor(Duration elapsed) {
    if (_cancelled) return KundiAvatarLongWaitAction.standing;
    if (!_danceIssued && elapsed >= entertainmentThreshold) {
      _danceIssued = true;
      return KundiAvatarLongWaitAction.dansing;
    }
    return KundiAvatarLongWaitAction.waiting;
  }

  void cancel() => _cancelled = true;
}
