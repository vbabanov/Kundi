import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../runtimes/kundi_system_speech/kundi_system_speech_controller.dart';
import '../../../runtimes/kundi_system_speech/kundi_system_speech_transport.dart';
import '../../../runtimes/kundi_system_speech/kundi_voice_qa_telemetry.dart';
import '../../kundi_behavior/application/kundi_behavior_controller.dart';
import '../../kundi_behavior/domain/kundi_behavior_event.dart';
import '../assistant_feature.dart';
import '../domain/assistant_entity.dart';
import 'assistant_controller.dart';

final kundiSystemSpeechTransportProvider =
    Provider<KundiSystemSpeechTransport>((ref) {
  return MethodChannelKundiSystemSpeechTransport();
});

final kundiSystemSpeechControllerProvider = StateNotifierProvider<
    KundiSystemSpeechController, KundiSpeechRecognitionState>((ref) {
  return KundiSystemSpeechController(
    transport: ref.watch(kundiSystemSpeechTransportProvider),
  );
});

final kundiVoiceAssistantCoordinatorProvider = StateNotifierProvider<
    KundiVoiceAssistantCoordinator, KundiSpeechRecognitionState>((ref) {
  final enabled = ref.watch(kundiAssistantEnabledProvider) &&
      ref.watch(kundiVoiceInputEnabledProvider);
  final speech = ref.watch(kundiSystemSpeechControllerProvider.notifier);
  return KundiVoiceAssistantCoordinator(
    enabled: enabled,
    speech: speech,
    ensureAssistantReady: () async {
      await ref.read(assistantControllerProvider.future);
    },
    sendVoiceMessage: (text, requestId) =>
        ref.read(assistantControllerProvider.notifier).sendMessage(
              text,
              clientMessageId: requestId,
              inputMode: AssistantInputMode.voice,
            ),
    behavior: (type, requestId) {
      if (!ref.read(kundiBehaviorCoreEnabledProvider)) return;
      ref.read(kundiBehaviorControllerProvider.notifier).dispatch(
            KundiBehaviorEvent(
              type: type,
              id: 'voice:$requestId:${type.name}',
              occurredAt: DateTime.now().toUtc(),
              fingerprint: 'voice:$requestId:${type.name}',
            ),
          );
    },
    settleBehavior: () {
      if (ref.read(kundiBehaviorCoreEnabledProvider)) {
        ref.read(kundiBehaviorControllerProvider.notifier).dismiss();
      }
    },
  );
});

class KundiVoiceAssistantCoordinator
    extends StateNotifier<KundiSpeechRecognitionState> {
  KundiVoiceAssistantCoordinator({
    required bool enabled,
    required KundiSystemSpeechController speech,
    required Future<void> Function() ensureAssistantReady,
    required Future<void> Function(String text, String requestId)
        sendVoiceMessage,
    required void Function(KundiBehaviorEventType type, String requestId)
        behavior,
    required void Function() settleBehavior,
  })  : _enabled = enabled,
        _speech = speech,
        _ensureAssistantReady = ensureAssistantReady,
        _sendVoiceMessage = sendVoiceMessage,
        _behavior = behavior,
        _settleBehavior = settleBehavior,
        super(speech.state) {
    KundiVoiceQaTelemetry.coordinatorCreated(_coordinatorInstanceId);
    _removeListener = _speech.addListener(_onSpeechState);
  }

  final bool _enabled;
  final KundiSystemSpeechController _speech;
  final Future<void> Function() _ensureAssistantReady;
  final Future<void> Function(String text, String requestId) _sendVoiceMessage;
  final void Function(KundiBehaviorEventType type, String requestId) _behavior;
  final void Function() _settleBehavior;
  late final void Function() _removeListener;
  final String _coordinatorInstanceId =
      KundiVoiceQaTelemetry.nextId('coordinator');
  final Set<String> _sentRequestIds = <String>{};
  final Map<String, int> _finalResultOrdinals = <String, int>{};
  int _assistantSendOrdinal = 0;
  String _lastErrorIdentity = '';
  bool _disposed = false;
  int _operationGeneration = 0;

  Future<KundiVoiceStartOutcome> beginHold(
    String locale, {
    String gestureId = '',
    String pointerSequenceId = '',
  }) async {
    if (!_enabled) return KundiVoiceStartOutcome.unavailable;
    final effectiveGestureId = gestureId.isEmpty
        ? KundiVoiceQaTelemetry.nextId('gesture-fallback')
        : gestureId;
    final effectivePointerSequenceId = pointerSequenceId.isEmpty
        ? KundiVoiceQaTelemetry.nextId('pointer-fallback')
        : pointerSequenceId;
    final correlation = KundiVoiceCorrelation(
      gestureId: effectiveGestureId,
      pointerSequenceId: effectivePointerSequenceId,
      coordinatorInstanceId: _coordinatorInstanceId,
    );
    KundiVoiceQaTelemetry.event(
      'voiceTurnCreated',
      gestureId: effectiveGestureId,
      pointerSequenceId: effectivePointerSequenceId,
      coordinatorInstanceId: _coordinatorInstanceId,
      state: 'created',
    );
    final outcome = await _speech.begin(locale, correlation: correlation);
    if (outcome == KundiVoiceStartOutcome.listening) {
      _behavior(
        KundiBehaviorEventType.assistantListeningStarted,
        _speech.state.requestId,
      );
    }
    return outcome;
  }

  Future<KundiSpeechPermission> requestPermission() =>
      _speech.requestPermission();

  Future<void> openAppSettings() => _speech.openAppSettings();

  Future<void> endHold() => _speech.stop();

  Future<void> cancel() async {
    _operationGeneration++;
    await _speech.cancel();
    _settleBehavior();
  }

  void _onSpeechState(KundiSpeechRecognitionState next) {
    if (_disposed) return;
    state = next;
    if (next.status == KundiSpeechRecognitionStatus.recognized) {
      unawaited(_sendFinalOnce(next));
    } else if (next.status == KundiSpeechRecognitionStatus.error) {
      final identity = '${next.requestId}:${next.errorCode}';
      if (identity != _lastErrorIdentity) {
        _lastErrorIdentity = identity;
        _behavior(KundiBehaviorEventType.assistantFailure, next.requestId);
      }
    }
  }

  Future<void> _sendFinalOnce(KundiSpeechRecognitionState recognized) async {
    final requestId = recognized.requestId;
    final text = recognized.finalText.trim();
    final correlation = _speech.correlationFor(requestId);
    final finalOrdinal = (_finalResultOrdinals[requestId] ?? 0) + 1;
    _finalResultOrdinals[requestId] = finalOrdinal;
    if (_disposed || requestId.isEmpty || text.isEmpty) {
      KundiVoiceQaTelemetry.event(
        'finalResultSuppressed',
        gestureId: correlation?.gestureId,
        pointerSequenceId: correlation?.pointerSequenceId,
        coordinatorInstanceId: _coordinatorInstanceId,
        recognitionRequestId: requestId,
        ordinal: finalOrdinal,
        textLength: text.length,
        outcome: _disposed ? 'disposed' : 'empty',
      );
      return;
    }
    if (!_sentRequestIds.add(requestId)) {
      KundiVoiceQaTelemetry.event(
        'finalResultSuppressed',
        gestureId: correlation?.gestureId,
        pointerSequenceId: correlation?.pointerSequenceId,
        coordinatorInstanceId: _coordinatorInstanceId,
        recognitionRequestId: requestId,
        ordinal: finalOrdinal,
        textLength: text.length,
        outcome: 'duplicate_request',
      );
      return;
    }
    KundiVoiceQaTelemetry.event(
      'finalResultAccepted',
      gestureId: correlation?.gestureId,
      pointerSequenceId: correlation?.pointerSequenceId,
      coordinatorInstanceId: _coordinatorInstanceId,
      recognitionRequestId: requestId,
      clientMessageId: requestId,
      ordinal: finalOrdinal,
      textLength: text.length,
    );
    _speech.markSending();
    final generation = _operationGeneration;
    try {
      await _ensureAssistantReady();
      if (_disposed || generation != _operationGeneration) return;
      final sendOrdinal = ++_assistantSendOrdinal;
      KundiVoiceQaTelemetry.event(
        'assistantSendStarted',
        gestureId: correlation?.gestureId,
        pointerSequenceId: correlation?.pointerSequenceId,
        coordinatorInstanceId: _coordinatorInstanceId,
        recognitionRequestId: requestId,
        clientMessageId: requestId,
        ordinal: sendOrdinal,
      );
      await _sendVoiceMessage(text, requestId);
      KundiVoiceQaTelemetry.event(
        'assistantSendCompleted',
        gestureId: correlation?.gestureId,
        pointerSequenceId: correlation?.pointerSequenceId,
        coordinatorInstanceId: _coordinatorInstanceId,
        recognitionRequestId: requestId,
        clientMessageId: requestId,
        ordinal: sendOrdinal,
      );
    } catch (_) {
      if (!_disposed && generation == _operationGeneration) {
        _speech.fail('assistant_unavailable');
        _behavior(KundiBehaviorEventType.assistantFailure, requestId);
      }
    } finally {
      if (!_disposed &&
          generation == _operationGeneration &&
          _speech.state.status != KundiSpeechRecognitionStatus.error) {
        _speech.settle();
        KundiVoiceQaTelemetry.event(
          'voiceTurnCompleted',
          gestureId: correlation?.gestureId,
          pointerSequenceId: correlation?.pointerSequenceId,
          coordinatorInstanceId: _coordinatorInstanceId,
          recognitionRequestId: requestId,
          clientMessageId: requestId,
          state: 'completed',
        );
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _operationGeneration++;
    _removeListener();
    KundiVoiceQaTelemetry.coordinatorDisposed(_coordinatorInstanceId);
    unawaited(_speech.cancel());
    super.dispose();
  }
}
