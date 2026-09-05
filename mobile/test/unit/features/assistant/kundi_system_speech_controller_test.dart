import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/assistant/application/kundi_voice_assistant_coordinator.dart';
import 'package:kundi_mobile/features/kundi_behavior/domain/kundi_behavior_event.dart';
import 'package:kundi_mobile/runtimes/kundi_system_speech/kundi_system_speech_controller.dart';
import 'package:kundi_mobile/runtimes/kundi_system_speech/kundi_system_speech_transport.dart';

void main() {
  test('release or cancel during TTS stop cannot start a late recognizer',
      () async {
    for (final cancel in [false, true]) {
      final transport =
          _FakeSpeechTransport(permission: KundiSpeechPermission.granted);
      final speech = KundiSystemSpeechController(transport: transport);
      final stoppingTts = Completer<void>();
      final coordinator = KundiVoiceAssistantCoordinator(
          enabled: true,
          speech: speech,
          interruptSpeech: () => stoppingTts.future,
          ensureAssistantReady: () async {},
          sendVoiceMessage: (_, __) async {},
          behavior: (_, __) {},
          settleBehavior: () {});
      final starting = coordinator.beginHold('ru-RU');
      expect(transport.startCalls, 0);
      final ending = cancel ? coordinator.cancel() : coordinator.endHold();
      stoppingTts.complete();
      await ending;
      expect(await starting, KundiVoiceStartOutcome.busy);
      expect(transport.startCalls, 0);
      coordinator.dispose();
      speech.dispose();
    }
  });

  test('new hold waits for TTS cancellation before system recognition',
      () async {
    final transport =
        _FakeSpeechTransport(permission: KundiSpeechPermission.granted);
    final speech = KundiSystemSpeechController(transport: transport);
    final stoppingTts = Completer<void>();
    final coordinator = KundiVoiceAssistantCoordinator(
        enabled: true,
        speech: speech,
        interruptSpeech: () => stoppingTts.future,
        ensureAssistantReady: () async {},
        sendVoiceMessage: (_, __) async {},
        behavior: (_, __) {},
        settleBehavior: () {});
    final starting = coordinator.beginHold('ru-RU');
    expect(transport.startCalls, 0);
    stoppingTts.complete();
    expect(await starting, KundiVoiceStartOutcome.listening);
    expect(transport.startCalls, 1);
    coordinator.dispose();
    speech.dispose();
  });

  test('terminal caches are bounded and evicted callbacks cannot send again',
      () async {
    final transport =
        _FakeSpeechTransport(permission: KundiSpeechPermission.granted);
    final speech = KundiSystemSpeechController(transport: transport);
    var sends = 0;
    final coordinator = KundiVoiceAssistantCoordinator(
        enabled: true,
        speech: speech,
        ensureAssistantReady: () async {},
        sendVoiceMessage: (_, __) async {
          sends++;
        },
        behavior: (_, __) {},
        settleBehavior: () {});
    String firstId = '';
    for (var i = 0; i < 300; i++) {
      await coordinator.beginHold('ru-RU');
      final id = transport.lastRequestId;
      if (i == 0) firstId = id;
      transport.emit('finalResult', id, text: 'Одинаковый вопрос');
      transport.emit('finalResult', id, text: 'Одинаковый вопрос');
      await _flush();
      expect(speech.terminalRequestCount, lessThanOrEqualTo(128));
      expect(coordinator.terminalRequestCount, lessThanOrEqualTo(128));
    }
    await coordinator.beginHold('ru-RU');
    transport.emit('finalResult', firstId,
        text: 'Поздний ответ после eviction');
    await _flush();
    expect(sends, 300);
    coordinator.dispose();
    speech.dispose();
    expect(speech.terminalRequestCount, 0);
    expect(coordinator.terminalRequestCount, 0);
  });
  test('first permission flow never starts listening until a second hold',
      () async {
    final transport = _FakeSpeechTransport(
      permission: KundiSpeechPermission.required,
      requestedPermission: KundiSpeechPermission.granted,
    );
    final controller = KundiSystemSpeechController(transport: transport);
    addTearDown(controller.dispose);

    expect(
      await controller.begin('ru-KZ'),
      KundiVoiceStartOutcome.permissionExplanationRequired,
    );
    expect(transport.startCalls, 0);
    expect(
      await controller.requestPermission(),
      KundiSpeechPermission.granted,
    );
    expect(transport.startCalls, 0);

    transport.permission = KundiSpeechPermission.granted;
    expect(
      await controller.begin('ru-KZ'),
      KundiVoiceStartOutcome.listening,
    );
    expect(transport.startCalls, 1);
    expect(transport.lastLocale, 'ru-KZ');
  });

  test('partial is not sent and duplicate final is sent once', () async {
    final transport = _FakeSpeechTransport(
      permission: KundiSpeechPermission.granted,
    );
    final speech = KundiSystemSpeechController(transport: transport);
    final sent = <({String text, String requestId})>[];
    final behaviors = <KundiBehaviorEventType>[];
    final coordinator = KundiVoiceAssistantCoordinator(
      enabled: true,
      speech: speech,
      ensureAssistantReady: () async {},
      sendVoiceMessage: (text, requestId) async {
        sent.add((text: text, requestId: requestId));
      },
      behavior: (type, _) => behaviors.add(type),
      settleBehavior: () {},
    );
    addTearDown(coordinator.dispose);
    addTearDown(speech.dispose);

    expect(
      await coordinator.beginHold('kk-KZ'),
      KundiVoiceStartOutcome.listening,
    );
    final requestId = transport.lastRequestId;
    transport.emit('partialResult', requestId, text: 'Бөлшек');
    await _flush();
    expect(sent, isEmpty);
    expect(coordinator.state.partialText, 'Бөлшек');

    transport.emit('finalResult', requestId, text: 'Бөлшек деген не');
    transport.emit('finalResult', requestId, text: 'Бөлшек деген не');
    await _flush();
    expect(sent, hasLength(1));
    expect(sent.single.text, 'Бөлшек деген не');
    expect(sent.single.requestId, requestId);
    expect(
        behaviors, contains(KundiBehaviorEventType.assistantListeningStarted));
  });

  test('cancel suppresses a late final result', () async {
    final transport = _FakeSpeechTransport(
      permission: KundiSpeechPermission.granted,
    );
    final speech = KundiSystemSpeechController(transport: transport);
    final sent = <String>[];
    final coordinator = KundiVoiceAssistantCoordinator(
      enabled: true,
      speech: speech,
      ensureAssistantReady: () async {},
      sendVoiceMessage: (text, _) async => sent.add(text),
      behavior: (_, __) {},
      settleBehavior: () {},
    );
    addTearDown(coordinator.dispose);
    addTearDown(speech.dispose);

    await coordinator.beginHold('ru-RU');
    final requestId = transport.lastRequestId;
    await coordinator.cancel();
    transport.emit('finalResult', requestId, text: 'Поздний результат');
    await _flush();
    expect(sent, isEmpty);
    expect(coordinator.state.status, KundiSpeechRecognitionStatus.idle);
  });

  test('disabled coordinator does not touch permission or recognizer',
      () async {
    final transport = _FakeSpeechTransport(
      permission: KundiSpeechPermission.granted,
    );
    final speech = KundiSystemSpeechController(transport: transport);
    final coordinator = KundiVoiceAssistantCoordinator(
      enabled: false,
      speech: speech,
      ensureAssistantReady: () async {},
      sendVoiceMessage: (_, __) async {},
      behavior: (_, __) {},
      settleBehavior: () {},
    );
    addTearDown(coordinator.dispose);
    addTearDown(speech.dispose);

    expect(
      await coordinator.beginHold('ru-RU'),
      KundiVoiceStartOutcome.unavailable,
    );
    expect(transport.availabilityCalls, 0);
    expect(transport.permissionCalls, 0);
    expect(transport.startCalls, 0);
  });

  test('two concurrent holds start at most one recognition request', () async {
    final availability = Completer<bool>();
    final transport = _FakeSpeechTransport(
      permission: KundiSpeechPermission.granted,
      availabilityResult: availability.future,
    );
    final controller = KundiSystemSpeechController(transport: transport);
    addTearDown(controller.dispose);

    final first = controller.begin('ru-RU');
    expect(
      await controller.begin('ru-RU'),
      KundiVoiceStartOutcome.busy,
    );
    availability.complete(true);
    expect(await first, KundiVoiceStartOutcome.listening);
    expect(transport.startCalls, 1);
  });

  test('cancel during availability prevents a late recognizer start', () async {
    final availability = Completer<bool>();
    final transport = _FakeSpeechTransport(
      permission: KundiSpeechPermission.granted,
      availabilityResult: availability.future,
    );
    final controller = KundiSystemSpeechController(transport: transport);
    addTearDown(controller.dispose);

    final pending = controller.begin('ru-RU');
    await controller.cancel();
    availability.complete(true);
    expect(await pending, KundiVoiceStartOutcome.busy);
    expect(transport.startCalls, 0);
    expect(controller.state.status, KundiSpeechRecognitionStatus.idle);
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _FakeSpeechTransport implements KundiSystemSpeechTransport {
  _FakeSpeechTransport({
    required this.permission,
    this.requestedPermission = KundiSpeechPermission.granted,
    this.availabilityResult,
  });

  final StreamController<KundiSystemSpeechEvent> _events =
      StreamController<KundiSystemSpeechEvent>.broadcast(sync: true);
  KundiSpeechPermission permission;
  KundiSpeechPermission requestedPermission;
  final Future<bool>? availabilityResult;
  int availabilityCalls = 0;
  int permissionCalls = 0;
  int startCalls = 0;
  String lastRequestId = '';
  String lastLocale = '';

  @override
  Stream<KundiSystemSpeechEvent> get events => _events.stream;

  @override
  Future<bool> availability() async {
    availabilityCalls++;
    return availabilityResult == null ? true : await availabilityResult!;
  }

  @override
  Future<KundiSpeechPermission> permissionStatus() async {
    permissionCalls++;
    return permission;
  }

  @override
  Future<KundiSpeechPermission> requestPermission() async =>
      requestedPermission;

  @override
  Future<bool> startListening({
    required String requestId,
    required String locale,
    bool partialResults = true,
    int maxResults = 3,
    bool qaTelemetryEnabled = false,
  }) async {
    startCalls++;
    lastRequestId = requestId;
    lastLocale = locale;
    emit('listeningStarted', requestId);
    return true;
  }

  void emit(String name, String requestId, {String? text}) {
    _events.add(KundiSystemSpeechEvent(name, <String, dynamic>{
      'requestId': requestId,
      if (text != null) 'text': text,
    }));
  }

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> cancelListening() async {}

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}
