import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'kundi_system_speech_transport.dart';
import 'kundi_voice_qa_telemetry.dart';

enum KundiSpeechRecognitionStatus {
  idle,
  requestingPermission,
  ready,
  listening,
  processing,
  recognized,
  sending,
  error,
  unavailable,
}

enum KundiVoiceStartOutcome {
  listening,
  permissionExplanationRequired,
  permissionPermanentlyDenied,
  unavailable,
  busy,
}

final class KundiSpeechRecognitionState {
  const KundiSpeechRecognitionState({
    this.status = KundiSpeechRecognitionStatus.idle,
    this.requestId = '',
    this.locale = 'ru-RU',
    this.partialText = '',
    this.finalText = '',
    this.errorCode = '',
  });

  final KundiSpeechRecognitionStatus status;
  final String requestId;
  final String locale;
  final String partialText;
  final String finalText;
  final String errorCode;

  KundiSpeechRecognitionState copyWith({
    KundiSpeechRecognitionStatus? status,
    String? requestId,
    String? locale,
    String? partialText,
    String? finalText,
    String? errorCode,
  }) =>
      KundiSpeechRecognitionState(
        status: status ?? this.status,
        requestId: requestId ?? this.requestId,
        locale: locale ?? this.locale,
        partialText: partialText ?? this.partialText,
        finalText: finalText ?? this.finalText,
        errorCode: errorCode ?? this.errorCode,
      );
}

class KundiSystemSpeechController
    extends StateNotifier<KundiSpeechRecognitionState> {
  KundiSystemSpeechController({
    required KundiSystemSpeechTransport transport,
    Uuid uuid = const Uuid(),
  })  : _transport = transport,
        _uuid = uuid,
        super(const KundiSpeechRecognitionState()) {
    KundiVoiceQaTelemetry.subscriptionCreated(_speechSubscriptionId);
    _events = _transport.events.listen(_handleEvent, onError: (_) {
      state = state.copyWith(
        status: KundiSpeechRecognitionStatus.error,
        errorCode: 'unknown',
      );
    });
  }

  final KundiSystemSpeechTransport _transport;
  final Uuid _uuid;
  final String _speechSubscriptionId =
      KundiVoiceQaTelemetry.nextId('speech-subscription');
  late final StreamSubscription<KundiSystemSpeechEvent> _events;
  final Map<String, KundiVoiceCorrelation> _correlations =
      <String, KundiVoiceCorrelation>{};
  final Map<String, int> _finalResultOrdinals = <String, int>{};
  bool _disposed = false;
  bool _beginning = false;
  int _operationGeneration = 0;

  KundiVoiceCorrelation? correlationFor(String requestId) =>
      _correlations[requestId];

  Future<KundiVoiceStartOutcome> begin(
    String locale, {
    KundiVoiceCorrelation? correlation,
  }) async {
    if (_disposed || _beginning || _isActive(state.status)) {
      return KundiVoiceStartOutcome.busy;
    }
    _beginning = true;
    final generation = _operationGeneration;
    final mappedRecognizerLocale = _recognizerLocaleFor(locale);
    try {
      if (!await _transport.availability()) {
        if (_isCurrent(generation)) {
          state = state.copyWith(
            status: KundiSpeechRecognitionStatus.unavailable,
          );
        }
        return KundiVoiceStartOutcome.unavailable;
      }
      if (!_isCurrent(generation)) return KundiVoiceStartOutcome.busy;
      final permission = await _transport.permissionStatus();
      if (!_isCurrent(generation)) return KundiVoiceStartOutcome.busy;
      if (permission == KundiSpeechPermission.permanentlyDenied) {
        state = state.copyWith(
          status: KundiSpeechRecognitionStatus.error,
          errorCode: 'permission_denied',
        );
        return KundiVoiceStartOutcome.permissionPermanentlyDenied;
      }
      if (permission != KundiSpeechPermission.granted) {
        state = state.copyWith(
          status: KundiSpeechRecognitionStatus.requestingPermission,
          errorCode: '',
        );
        return KundiVoiceStartOutcome.permissionExplanationRequired;
      }
      final requestId = _uuid.v4();
      if (correlation != null) _correlations[requestId] = correlation;
      KundiVoiceQaTelemetry.event(
        'recognitionStartRequested',
        gestureId: correlation?.gestureId,
        pointerSequenceId: correlation?.pointerSequenceId,
        coordinatorInstanceId: correlation?.coordinatorInstanceId,
        speechSubscriptionId: _speechSubscriptionId,
        recognitionRequestId: requestId,
        state: 'processing',
        sessionLocale: locale,
        mappedRecognizerLocale: mappedRecognizerLocale,
      );
      state = KundiSpeechRecognitionState(
        status: KundiSpeechRecognitionStatus.processing,
        requestId: requestId,
        locale: locale,
      );
      final accepted = await _transport.startListening(
        requestId: requestId,
        locale: locale,
        qaTelemetryEnabled: kundiVoiceQaTelemetryEnabled,
      );
      if (!_isCurrent(generation)) {
        if (accepted) await _transport.cancelListening();
        return KundiVoiceStartOutcome.busy;
      }
      if (!accepted) {
        state = state.copyWith(
          status: KundiSpeechRecognitionStatus.error,
          errorCode: 'unavailable',
        );
        return KundiVoiceStartOutcome.unavailable;
      }
      KundiVoiceQaTelemetry.event(
        'recognitionStartAccepted',
        gestureId: correlation?.gestureId,
        pointerSequenceId: correlation?.pointerSequenceId,
        coordinatorInstanceId: correlation?.coordinatorInstanceId,
        speechSubscriptionId: _speechSubscriptionId,
        recognitionRequestId: requestId,
        state: 'listening',
        sessionLocale: locale,
        mappedRecognizerLocale: mappedRecognizerLocale,
      );
      return KundiVoiceStartOutcome.listening;
    } catch (_) {
      if (_isCurrent(generation)) {
        state = state.copyWith(
          status: KundiSpeechRecognitionStatus.error,
          errorCode: 'unavailable',
        );
      }
      return KundiVoiceStartOutcome.unavailable;
    } finally {
      _beginning = false;
    }
  }

  static String _recognizerLocaleFor(String sessionLocale) =>
      switch (sessionLocale.trim().toLowerCase()) {
        'kk' || 'kk-kz' => 'kk-KZ',
        'ru' || 'ru-kz' || 'ru-ru' => 'ru-RU',
        _ => 'ru-RU',
      };

  Future<KundiSpeechPermission> requestPermission() async {
    if (_disposed) return KundiSpeechPermission.denied;
    final generation = _operationGeneration;
    state = state.copyWith(
        status: KundiSpeechRecognitionStatus.requestingPermission);
    try {
      final permission = await _transport.requestPermission();
      if (_isCurrent(generation)) {
        state = state.copyWith(
          status: permission == KundiSpeechPermission.granted
              ? KundiSpeechRecognitionStatus.ready
              : KundiSpeechRecognitionStatus.error,
          errorCode: permission == KundiSpeechPermission.granted
              ? ''
              : 'permission_denied',
        );
      }
      return permission;
    } catch (_) {
      if (_isCurrent(generation)) fail('permission_denied');
      return KundiSpeechPermission.denied;
    }
  }

  Future<void> openAppSettings() => _transport.openAppSettings();

  Future<void> stop() async {
    if (!_isActive(state.status)) return;
    final correlation = _correlations[state.requestId];
    KundiVoiceQaTelemetry.event(
      'recognitionStopRequested',
      gestureId: correlation?.gestureId,
      pointerSequenceId: correlation?.pointerSequenceId,
      coordinatorInstanceId: correlation?.coordinatorInstanceId,
      speechSubscriptionId: _speechSubscriptionId,
      recognitionRequestId: state.requestId,
      state: state.status.name,
    );
    state = state.copyWith(status: KundiSpeechRecognitionStatus.processing);
    await _transport.stopListening();
  }

  Future<void> cancel() async {
    if (_disposed) return;
    _operationGeneration++;
    try {
      await _transport.cancelListening();
    } catch (_) {
      // Cancellation is best-effort; local state must still be cleared.
    }
    if (_disposed) return;
    state = const KundiSpeechRecognitionState();
  }

  void markSending() {
    state = state.copyWith(status: KundiSpeechRecognitionStatus.sending);
  }

  void settle() {
    state = const KundiSpeechRecognitionState(
        status: KundiSpeechRecognitionStatus.ready);
  }

  void fail(String code) {
    state = state.copyWith(
      status: KundiSpeechRecognitionStatus.error,
      errorCode: code,
    );
  }

  void _handleEvent(KundiSystemSpeechEvent event) {
    if (_disposed) return;
    if (event.requestId.isNotEmpty && event.requestId != state.requestId) {
      if (event.name == 'finalResult') {
        final correlation = _correlations[event.requestId];
        KundiVoiceQaTelemetry.event(
          'finalResultSuppressed',
          gestureId: correlation?.gestureId,
          pointerSequenceId: correlation?.pointerSequenceId,
          coordinatorInstanceId: correlation?.coordinatorInstanceId,
          speechSubscriptionId: _speechSubscriptionId,
          recognitionRequestId: event.requestId,
          outcome: 'request_mismatch',
        );
      }
      return;
    }
    switch (event.name) {
      case 'readyForSpeech':
      case 'listeningStarted':
      case 'beginningOfSpeech':
        state = state.copyWith(status: KundiSpeechRecognitionStatus.listening);
      case 'partialResult':
        state = state.copyWith(
          status: KundiSpeechRecognitionStatus.listening,
          partialText: (event.payload['text'] ?? '').toString(),
        );
      case 'endOfSpeech':
        state = state.copyWith(status: KundiSpeechRecognitionStatus.processing);
      case 'finalResult':
        final text = (event.payload['text'] ?? '').toString().trim();
        final ordinal = (_finalResultOrdinals[event.requestId] ?? 0) + 1;
        _finalResultOrdinals[event.requestId] = ordinal;
        final correlation = _correlations[event.requestId];
        KundiVoiceQaTelemetry.event(
          'finalResultReceived',
          gestureId: correlation?.gestureId,
          pointerSequenceId: correlation?.pointerSequenceId,
          coordinatorInstanceId: correlation?.coordinatorInstanceId,
          speechSubscriptionId: _speechSubscriptionId,
          recognitionRequestId: event.requestId,
          ordinal: ordinal,
          textLength: text.length,
        );
        if (text.isNotEmpty) {
          state = state.copyWith(
            status: KundiSpeechRecognitionStatus.recognized,
            finalText: text,
            partialText: '',
          );
        }
      case 'recognitionCancelled':
        state = const KundiSpeechRecognitionState();
      case 'noSpeech':
      case 'recognitionError':
        state = state.copyWith(
          status: KundiSpeechRecognitionStatus.error,
          errorCode: (event.payload['code'] ?? 'unknown').toString(),
          partialText: '',
        );
    }
  }

  bool _isActive(KundiSpeechRecognitionStatus status) =>
      status == KundiSpeechRecognitionStatus.listening ||
      status == KundiSpeechRecognitionStatus.processing;

  bool _isCurrent(int generation) =>
      !_disposed && generation == _operationGeneration;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _operationGeneration++;
    unawaited(_events.cancel());
    KundiVoiceQaTelemetry.subscriptionCancelled(_speechSubscriptionId);
    unawaited(_transport.cancelListening());
    unawaited(_transport.dispose());
    super.dispose();
  }
}
