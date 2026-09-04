import 'dart:convert';

import 'package:flutter/foundation.dart';

const bool kundiVoiceQaTelemetryEnabled = bool.fromEnvironment(
  'ENABLE_KUNDI_VOICE_QA_TELEMETRY',
  defaultValue: false,
);

/// Default-off correlation telemetry for physical-device voice QA.
///
/// The deliberately narrow schema prevents recognized text, credentials, and
/// user data from entering logs. Keep all identifiers opaque.
abstract final class KundiVoiceQaTelemetry {
  static int _idSequence = 0;
  static int _coordinatorCreateCount = 0;
  static int _activeCoordinatorCount = 0;
  static int _speechSubscriptionCount = 0;

  static String nextId(String prefix) => '$prefix-${++_idSequence}';

  static void coordinatorCreated(String coordinatorInstanceId) {
    _coordinatorCreateCount++;
    _activeCoordinatorCount++;
    event(
      'coordinatorCreated',
      coordinatorInstanceId: coordinatorInstanceId,
      count: _coordinatorCreateCount,
      activeCount: _activeCoordinatorCount,
    );
  }

  static void coordinatorDisposed(String coordinatorInstanceId) {
    if (_activeCoordinatorCount > 0) _activeCoordinatorCount--;
    event(
      'coordinatorDisposed',
      coordinatorInstanceId: coordinatorInstanceId,
      activeCount: _activeCoordinatorCount,
    );
  }

  static void subscriptionCreated(String speechSubscriptionId) {
    _speechSubscriptionCount++;
    event(
      'speechSubscriptionCreated',
      speechSubscriptionId: speechSubscriptionId,
      count: _speechSubscriptionCount,
    );
  }

  static void subscriptionCancelled(String speechSubscriptionId) {
    if (_speechSubscriptionCount > 0) _speechSubscriptionCount--;
    event(
      'speechSubscriptionCancelled',
      speechSubscriptionId: speechSubscriptionId,
      count: _speechSubscriptionCount,
    );
  }

  static void event(
    String name, {
    String? gestureId,
    String? pointerSequenceId,
    String? coordinatorInstanceId,
    String? speechSubscriptionId,
    String? recognitionRequestId,
    String? clientMessageId,
    int? nativeSessionGeneration,
    int? gestureGeneration,
    int? ordinal,
    int? count,
    int? activeCount,
    int? textLength,
    String? state,
    String? outcome,
    String? reason,
    String? sessionLocale,
    String? mappedRecognizerLocale,
  }) {
    if (!kundiVoiceQaTelemetryEnabled) return;
    debugPrint(
      '[KUNDI_VOICE_QA] ${jsonEncode(<String, Object>{
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'event': name,
            if (gestureId != null) 'gestureId': gestureId,
            if (pointerSequenceId != null)
              'pointerSequenceId': pointerSequenceId,
            if (coordinatorInstanceId != null)
              'coordinatorInstanceId': coordinatorInstanceId,
            if (speechSubscriptionId != null)
              'speechSubscriptionId': speechSubscriptionId,
            if (recognitionRequestId != null)
              'recognitionRequestId': recognitionRequestId,
            if (clientMessageId != null) 'clientMessageId': clientMessageId,
            if (nativeSessionGeneration != null)
              'nativeSessionGeneration': nativeSessionGeneration,
            if (gestureGeneration != null)
              'gestureGeneration': gestureGeneration,
            if (ordinal != null) 'ordinal': ordinal,
            if (count != null) 'count': count,
            if (activeCount != null) 'activeCount': activeCount,
            if (textLength != null) 'textLength': textLength,
            if (state != null) 'state': state,
            if (outcome != null) 'outcome': outcome,
            if (reason != null) 'reason': reason,
            if (sessionLocale != null) 'sessionLocale': sessionLocale,
            if (mappedRecognizerLocale != null)
              'mappedRecognizerLocale': mappedRecognizerLocale,
          })}',
    );
  }
}

final class KundiVoiceCorrelation {
  const KundiVoiceCorrelation({
    required this.gestureId,
    required this.pointerSequenceId,
    required this.coordinatorInstanceId,
  });

  final String gestureId;
  final String pointerSequenceId;
  final String coordinatorInstanceId;
}
