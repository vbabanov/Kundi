import 'dart:collection';

import 'package:flutter/foundation.dart';

abstract final class KundiHomeAvatarTraceName {
  static const loadingDecodeStarted = 'loadingDecodeStarted';
  static const loadingDecodeReady = 'loadingDecodeReady';
  static const homeHeroMounted = 'homeHeroMounted';
  static const loadingLayerPainted = 'loadingLayerPainted';
  static const textureIdAvailable = 'textureIdAvailable';
  static const textureMounted = 'textureMounted';
  static const nativeFirstFrame = 'nativeFirstFrame';
  static const presentationPrimingRequested = 'presentationPrimingRequested';
  static const presentationPrimed = 'presentationPrimed';
  static const presentationPrimeTimedOut = 'presentationPrimeTimedOut';
  static const revealGateOpened = 'revealGateOpened';
  static const loadingFadeStarted = 'loadingFadeStarted';
  static const loadingFadeCompleted = 'loadingFadeCompleted';
  static const handoffCompleted = 'handoffCompleted';
  static const greetingStarted = 'greetingStarted';
  static const greetingCompleted = 'greetingCompleted';
  static const standingFrozen = 'standingFrozen';
}

typedef KundiHomeAvatarDiagnosticRecorder =
    void Function(
      String name, {
      required int generation,
      int? textureId,
      Map<String, Object?> payload,
    });

@immutable
final class KundiHomeAvatarTraceEvent {
  const KundiHomeAvatarTraceEvent({
    required this.name,
    required this.timestamp,
    required this.generation,
    required this.textureId,
    required this.payload,
  });

  final String name;
  final DateTime timestamp;
  final int generation;
  final int? textureId;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => <String, Object?>{
    'event': name,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'generation': generation,
    'textureId': textureId,
    if (payload.isNotEmpty) 'payload': payload,
  };
}

/// Bounded debug/profile-only diagnostics with a typed in-memory snapshot.
///
/// Release builds do not collect or emit events. No event contains user data.
final class KundiHomeAvatarDiagnostics {
  KundiHomeAvatarDiagnostics._();

  static final KundiHomeAvatarDiagnostics instance =
      KundiHomeAvatarDiagnostics._();
  static const int _maximumEvents = 96;

  final Queue<KundiHomeAvatarTraceEvent> _events =
      Queue<KundiHomeAvatarTraceEvent>();

  bool get _enabled => kDebugMode || kProfileMode;

  List<KundiHomeAvatarTraceEvent> get snapshot =>
      List<KundiHomeAvatarTraceEvent>.unmodifiable(_events);

  void record(
    String name, {
    required int generation,
    int? textureId,
    Map<String, Object?> payload = const <String, Object?>{},
  }) {
    if (!_enabled) return;
    final event = KundiHomeAvatarTraceEvent(
      name: name,
      timestamp: DateTime.now(),
      generation: generation,
      textureId: textureId,
      payload: Map<String, Object?>.unmodifiable(payload),
    );
    if (_events.length == _maximumEvents) {
      _events.removeFirst();
    }
    _events.addLast(event);
  }

  @visibleForTesting
  void clear() => _events.clear();
}

enum KundiGreetingCompletionReason { finished, interrupted, cancelled }

/// Records semantic lifecycle boundaries once for the active renderer generation.
///
/// This intentionally owns diagnostics only: it does not schedule timers or
/// change animation commands, so stale callbacks can be ignored without
/// affecting the visible avatar.
final class KundiHomeAvatarLifecycleTelemetry {
  KundiHomeAvatarLifecycleTelemetry({required this.recordDiagnostic});

  final KundiHomeAvatarDiagnosticRecorder recordDiagnostic;

  int? _activeGeneration;
  bool _handoffRecorded = false;
  bool _greetingRecorded = false;
  _ActiveGreeting? _activeGreeting;

  void beginGeneration(int generation) {
    _activeGeneration = generation;
    _handoffRecorded = false;
    _greetingRecorded = false;
    _activeGreeting = null;
  }

  void suppressGeneration(int generation) {
    if (_activeGeneration != generation) return;
    _handoffRecorded = false;
    _greetingRecorded = false;
    _activeGreeting = null;
    _activeGeneration = null;
  }

  bool recordHandoffCompleted({
    required int generation,
    required int? textureId,
    required String mode,
    required int durationMs,
  }) {
    if (_activeGeneration != generation || _handoffRecorded) return false;
    _handoffRecorded = true;
    recordDiagnostic(
      KundiHomeAvatarTraceName.handoffCompleted,
      generation: generation,
      textureId: textureId,
      payload: <String, Object?>{'mode': mode, 'durationMs': durationMs},
    );
    return true;
  }

  bool startGreeting({
    required int generation,
    required int? textureId,
    required String identity,
    required String animationName,
    required int durationMs,
  }) {
    if (_activeGeneration != generation ||
        _greetingRecorded ||
        _activeGreeting != null) {
      return false;
    }
    _greetingRecorded = true;
    _activeGreeting = _ActiveGreeting(
      generation: generation,
      identity: identity,
      animationName: animationName,
      durationMs: durationMs,
    );
    recordDiagnostic(
      KundiHomeAvatarTraceName.greetingStarted,
      generation: generation,
      textureId: textureId,
      payload: <String, Object?>{
        'animationName': animationName,
        'durationMs': durationMs,
      },
    );
    return true;
  }

  bool completeGreeting({
    required int generation,
    required int? textureId,
    required String identity,
    required KundiGreetingCompletionReason reason,
  }) {
    final active = _activeGreeting;
    if (_activeGeneration != generation ||
        active == null ||
        active.generation != generation ||
        active.identity != identity) {
      return false;
    }
    _activeGreeting = null;
    recordDiagnostic(
      KundiHomeAvatarTraceName.greetingCompleted,
      generation: generation,
      textureId: textureId,
      payload: <String, Object?>{
        'animationName': active.animationName,
        'durationMs': active.durationMs,
        'completionReason': reason.name,
      },
    );
    return true;
  }
}

final class _ActiveGreeting {
  const _ActiveGreeting({
    required this.generation,
    required this.identity,
    required this.animationName,
    required this.durationMs,
  });

  final int generation;
  final String identity;
  final String animationName;
  final int durationMs;
}
