import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/assistant/application/kundi_tts_coordinator.dart';
import 'package:kundi_mobile/features/assistant/domain/assistant_entity.dart';
import 'package:kundi_mobile/runtimes/kundi_tts/kundi_tts_transport.dart';
import 'package:kundi_mobile/runtimes/kundi_tts/kundi_tts_avatar_driver.dart';
import 'package:kundi_mobile/runtimes/kundi_native_avatar/kundi_native_avatar_controller.dart';
import 'package:kundi_mobile/runtimes/kundi_native_avatar/kundi_native_avatar_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const expression = KundiFacialExpression(
    emotion: KundiNativeAvatarEmotion.joy,
    intensity: 0.4,
  );
  test('viseme during delayed body transition does not swallow Talking',
      () async {
    final wire = FakeAvatar()
      ..delayedCommand = 'setEmotion'
      ..delay = Completer<void>();
    final controller = KundiNativeAvatarController(wire);
    final driver = KundiTtsAvatarDriver();
    addTearDown(controller.dispose);
    final started = driver.apply(controller,
        const KundiTtsState(status: KundiTtsStatus.speaking, messageId: 'm'));
    await driver.apply(
        controller,
        const KundiTtsState(
            status: KundiTtsStatus.speaking, messageId: 'm', viseme: 'A'));
    wire.delay!.complete();
    await started;
    expect(wire.commands.where((c) => c['name'] == 'playTalking').length, 1);
    expect((wire.commands.last['payload'] as Map)['viseme'], 'A');
  });
  test('defaults off, voice-only once, typed and replay stay silent', () async {
    expect(kundiTtsEnabledByDefault, isFalse);
    final transport = FakeTts();
    var issuances = 0;
    final tts = KundiTtsCoordinator(
        enabled: true,
        transport: transport,
        authorize: (m) async {
          issuances++;
          return authorization(m);
        });
    addTearDown(tts.dispose);
    await tts.speakResponse(result(mode: 'text'), expectedEpoch: tts.epoch);
    await tts.speakResponse(result(replayed: true), expectedEpoch: tts.epoch);
    expect(issuances, 0);
    final reply = result();
    await tts.speakResponse(reply, expectedEpoch: tts.epoch);
    await tts.speakResponse(reply, expectedEpoch: tts.epoch);
    expect(transport.texts, [reply.assistantMessage.content]);
    expect(tts.state.status, KundiTtsStatus.synthesizing);
    transport.emit(KundiTtsEventType.playbackStarted);
    expect(tts.state.status, KundiTtsStatus.speaking);
    expect(tts.state.expression.emotion, KundiNativeAvatarEmotion.joy);
    expect(tts.state.expression.intensity, 0.4);
    transport.emit(KundiTtsEventType.visemeDue, viseme: 'A');
    expect(tts.state.viseme, 'A');
    expect(tts.state.expression.emotion, KundiNativeAvatarEmotion.joy);
    transport.emit(KundiTtsEventType.playbackCompleted);
    expect(tts.state.status, KundiTtsStatus.idle);
    await tts.speakResponse(reply, expectedEpoch: tts.epoch);
    expect(issuances, 1);
  });
  test('TTS off never subscribes or requests credentials', () async {
    final transport = FakeTts();
    final tts = KundiTtsCoordinator(
        enabled: false,
        transport: transport,
        authorize: (_) async => throw StateError('must not be called'));
    await tts.speakResponse(result(), expectedEpoch: tts.epoch);
    await tts.cancel();
    tts.dispose();
    expect(transport.subscriptions, 0);
    expect(transport.cancels, 0);
  });
  test('interrupt pending token and late playback callbacks', () async {
    final transport = FakeTts();
    final pending = Completer<Map<String, dynamic>>();
    final tts = KundiTtsCoordinator(
        enabled: true, transport: transport, authorize: (_) => pending.future);
    addTearDown(tts.dispose);
    final epoch = tts.epoch;
    final speaking = tts.speakResponse(result(), expectedEpoch: epoch);
    await tts.cancel();
    pending.complete(authorization(result().assistantMessage));
    await speaking;
    expect(transport.texts, isEmpty);
    await tts.speakResponse(result(), expectedEpoch: epoch);
    transport.emit(KundiTtsEventType.playbackStarted);
    expect(tts.state.status, KundiTtsStatus.idle);
  });
  test('background stops audio; foreground/history never resumes it', () async {
    final transport = FakeTts();
    final tts = KundiTtsCoordinator(
        enabled: true,
        transport: transport,
        authorize: (m) async => authorization(m));
    addTearDown(tts.dispose);
    await tts.speakResponse(result(), expectedEpoch: tts.epoch);
    transport.emit(KundiTtsEventType.playbackStarted);
    tts.didChangeAppLifecycleState(AppLifecycleState.paused);
    transport.emit(KundiTtsEventType.visemeDue, viseme: 'O');
    expect(tts.state.status, KundiTtsStatus.idle);
    expect(tts.state.viseme, 'Neutral');
    tts.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(transport.texts.length, 1);
  });
  test('error keeps assistant text and never needs an avatar to play',
      () async {
    final transport = FakeTts();
    final tts = KundiTtsCoordinator(
        enabled: true,
        transport: transport,
        authorize: (m) async => authorization(m));
    addTearDown(tts.dispose);
    final reply = result();
    await tts.speakResponse(reply, expectedEpoch: tts.epoch);
    expect(transport.texts, ['Финальный ответ.']);
    transport.emit(KundiTtsEventType.speechError);
    expect(tts.state.errorMessage, 'Не удалось озвучить ответ');
    expect(reply.assistantMessage.content, 'Финальный ответ.');
  });
  test('invalid message binding and expiry never reach native SDK', () async {
    for (final invalid in ['message', 'expiry']) {
      final transport = FakeTts();
      final tts = KundiTtsCoordinator(
          enabled: true,
          transport: transport,
          authorize: (m) async {
            final auth = authorization(m);
            if (invalid == 'message') auth['message_id'] = 'other';
            if (invalid == 'expiry') {
              auth['expires_at'] = DateTime.now().toIso8601String();
            }
            return auth;
          });
      await tts.speakResponse(result(), expectedEpoch: tts.epoch);
      expect(transport.texts, isEmpty);
      expect(tts.state.status, KundiTtsStatus.error);
      tts.dispose();
    }
  });
  test('avatar Waiting Talking neutral Standing; mouth does not restart body',
      () async {
    final wire = FakeAvatar();
    final controller = KundiNativeAvatarController(wire);
    final driver = KundiTtsAvatarDriver();
    addTearDown(controller.dispose);
    await driver.apply(
        controller,
        const KundiTtsState(
            status: KundiTtsStatus.synthesizing,
            messageId: 'm',
            expression: expression));
    await driver.apply(
        controller,
        const KundiTtsState(
            status: KundiTtsStatus.speaking,
            messageId: 'm',
            expression: expression));
    await driver.apply(
        controller,
        const KundiTtsState(
            status: KundiTtsStatus.speaking,
            messageId: 'm',
            viseme: 'A',
            expression: expression));
    expect(wire.commands.where((c) => c['name'] == 'playTalking').length, 1);
    expect(wire.commands.any((c) => c['name'] == 'resetFace'), isFalse);
    final emotion = wire.commands.firstWhere((c) => c['name'] == 'setEmotion');
    expect((emotion['payload'] as Map)['emotion'], 'Joy');
    expect((emotion['payload'] as Map)['intensity'], 0.4);
    expect(wire.commands.last['name'], 'setViseme');
    expect((wire.commands.last['payload'] as Map)['viseme'], 'A');
    await driver.apply(controller, const KundiTtsState());
    expect(wire.commands.last['name'], 'settleRestPose');
    final lastMouthCommand = wire.commands.lastWhere(
      (c) => c['name'] == 'clearViseme' || c['name'] == 'setViseme',
    );
    expect(lastMouthCommand['name'], 'clearViseme');
    expect(wire.commands.any((c) => c['name'] == 'playWaiting'), isTrue);
  });
}

AssistantMessageResult result({
  String mode = 'voice',
  bool replayed = false,
  String emotion = 'joy',
  double emotionIntensity = 0.4,
}) {
  final now = DateTime.utc(2026);
  return AssistantMessageResult(
    userMessage: AssistantMessageEntity(
        id: 'u',
        sessionId: 's',
        role: 'user',
        content: 'User transcript must not reach TTS',
        inputMode: mode,
        responseMode: '',
        createdAt: now),
    assistantMessage: AssistantMessageEntity(
        id: 'm',
        sessionId: 's',
        role: 'assistant',
        content: 'Финальный ответ.',
        inputMode: 'text',
        responseMode: '',
        createdAt: now),
    responseMode: '',
    helpLevel: '',
    emotion: emotion,
    emotionIntensity: emotionIntensity,
    animationCue: '',
    suggestions: const [],
    replayed: replayed,
  );
}

Map<String, dynamic> authorization(AssistantMessageEntity message) => {
      'message_id': message.id,
      'authorization_token': 'fake-ephemeral-token',
      'expires_at':
          DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
      'audio_format': 'raw-24khz-16bit-mono-pcm',
      'sample_rate_hz': 24000,
      'channels': 1,
      'bits_per_sample': 16,
    };

class FakeTts implements KundiTtsTransport {
  final stream = StreamController<KundiTtsEvent>.broadcast(sync: true);
  final texts = <String>[];
  int generation = 0;
  int subscriptions = 0;
  int cancels = 0;
  @override
  Stream<KundiTtsEvent> get events {
    subscriptions++;
    return stream.stream;
  }

  void emit(KundiTtsEventType type, {String viseme = 'Neutral'}) =>
      stream.add(KundiTtsEvent(generation, type, viseme));
  @override
  Future<bool> speak(
      int generation, String text, Map<String, dynamic> auth) async {
    this.generation = generation;
    texts.add(text);
    return true;
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }

  @override
  Future<void> dispose() async {
    await stream.close();
  }
}

class FakeAvatar implements KundiNativeAvatarTransport {
  String? delayedCommand;
  Completer<void>? delay;
  final commands = <Map<String, Object>>[];
  @override
  Stream<Object?> get events => const Stream.empty();
  @override
  Future<Object?> send(Map<String, Object> envelope) async {
    commands.add(envelope);
    if (envelope['name'] == delayedCommand) await delay?.future;
    return null;
  }

  @override
  Future<void> dispose() async {}
}
