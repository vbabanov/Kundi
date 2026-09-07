import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/runtimes/kundi_native_avatar/kundi_native_avatar_controller.dart';
import 'package:kundi_mobile/runtimes/kundi_native_avatar/kundi_native_avatar_protocol.dart';

void main() {
  test('controller serializes native-specific versioned commands', () async {
    final transport = _FakeTransport();
    final controller = KundiNativeAvatarController(transport);

    await controller.playTalking(2);
    await controller.playCelebration();
    await controller.settleRestPose();
    await controller.startPresentationPriming(
      rendererGeneration: 7,
      textureId: 42,
    );
    await controller.freeze();
    await controller.setEmotion(KundiNativeAvatarEmotion.joy, intensity: 0.4);
    await controller.setViseme(KundiNativeAvatarViseme.o, weight: 0.75);
    await controller.setViseme(KundiNativeAvatarViseme.neutral);

    expect(transport.commands, [
      {
        'version': 1,
        'kind': 'command',
        'name': 'playTalking',
        'payload': {'variant': 2},
      },
      {
        'version': 1,
        'kind': 'command',
        'name': 'playCelebration',
        'payload': <String, Object>{},
      },
      {
        'version': 1,
        'kind': 'command',
        'name': 'settleRestPose',
        'payload': <String, Object>{},
      },
      {
        'version': 1,
        'kind': 'command',
        'name': 'startPresentationPriming',
        'payload': {
          'rendererGeneration': 7,
          'textureId': 42,
        },
      },
      {
        'version': 1,
        'kind': 'command',
        'name': 'freeze',
        'payload': <String, Object>{},
      },
      {
        'version': 1,
        'kind': 'command',
        'name': 'setEmotion',
        'payload': {'emotion': 'Joy', 'intensity': 0.4},
      },
      {
        'version': 1,
        'kind': 'command',
        'name': 'setViseme',
        'payload': {'viseme': 'O', 'weight': 0.75},
      },
      {
        'version': 1,
        'kind': 'command',
        'name': 'clearViseme',
        'payload': <String, Object>{},
      },
    ]);

    await controller.dispose();
  });

  test('facial intensity and viseme weight reject values outside 0..1',
      () async {
    final controller = KundiNativeAvatarController(_FakeTransport());
    addTearDown(controller.dispose);

    expect(
      () => controller.setEmotion(
        KundiNativeAvatarEmotion.joy,
        intensity: 1.1,
      ),
      throwsRangeError,
    );
    expect(
      () => controller.setViseme(KundiNativeAvatarViseme.a, weight: -0.1),
      throwsRangeError,
    );
  });

  test('invalid native event becomes rendererError without crashing', () async {
    final transport = _FakeTransport();
    final controller = KundiNativeAvatarController(transport);
    final eventFuture = controller.events.first;

    transport.emit('not an envelope');

    final event = await eventFuture;
    expect(event.name, 'rendererError');
    expect(event.payload['code'], 'invalid_event');
    await controller.dispose();
  });

  test('dispose is idempotent and commands after dispose fail', () async {
    final transport = _FakeTransport();
    final controller = KundiNativeAvatarController(transport);

    await controller.dispose();
    await controller.dispose();

    expect(transport.disposeCalls, 1);
    expect(controller.playIdle, throwsStateError);
  });
}

final class _FakeTransport implements KundiNativeAvatarTransport {
  final StreamController<Object?> _events = StreamController<Object?>();
  final List<Map<String, Object>> commands = [];
  int disposeCalls = 0;

  @override
  Stream<Object?> get events => _events.stream;

  void emit(Object? value) => _events.add(value);

  @override
  Future<Object?> send(Map<String, Object> envelope) async {
    commands.add(envelope);
    return const <String, Object>{'accepted': true};
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await _events.close();
  }
}
