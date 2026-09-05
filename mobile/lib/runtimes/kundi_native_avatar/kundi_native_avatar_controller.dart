import 'dart:async';

import 'kundi_native_avatar_protocol.dart';

abstract interface class KundiNativeAvatarTransport {
  Stream<Object?> get events;
  Future<Object?> send(Map<String, Object> envelope);
  Future<void> dispose();
}

final class KundiNativeAvatarController {
  KundiNativeAvatarController(KundiNativeAvatarTransport transport)
      : _transport = transport {
    _subscription = _transport.events.listen(
      _onRawEvent,
      onError: _onTransportError,
    );
  }

  final KundiNativeAvatarTransport _transport;
  final StreamController<KundiNativeAvatarEvent> _events =
      StreamController<KundiNativeAvatarEvent>.broadcast();
  StreamSubscription<Object?>? _subscription;
  bool _disposed = false;

  Stream<KundiNativeAvatarEvent> get events => _events.stream;

  Future<void> setVisible(bool visible) =>
      _send('setVisible', <String, Object>{'visible': visible});

  Future<void> playIdle() => _send('playIdle');
  Future<void> playWaiting() => _send('playWaiting');

  Future<void> playTalking(int variant) =>
      _send('playTalking', <String, Object>{'variant': variant});

  Future<void> playCelebration() => _send('playCelebration');

  Future<void> settleRestPose() => _send('settleRestPose');

  Future<void> startPresentationPriming({
    required int rendererGeneration,
    required int textureId,
  }) =>
      _send('startPresentationPriming', <String, Object>{
        'rendererGeneration': rendererGeneration,
        'textureId': textureId,
      });

  Future<void> freeze() => _send('freeze');

  Future<void> setEmotion(KundiNativeAvatarEmotion emotion) =>
      _send('setEmotion', <String, Object>{'emotion': emotion.wireName});

  Future<void> blink() => _send('blink');

  Future<void> setViseme(KundiNativeAvatarViseme viseme) =>
      viseme == KundiNativeAvatarViseme.neutral
          ? resetFace()
          : _send('setViseme', <String, Object>{'viseme': viseme.wireName});

  Future<void> resetFace() => _send('resetFace');

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    await _transport.dispose();
    await _events.close();
  }

  Future<void> _send(
    String name, [
    Map<String, Object> payload = const {},
  ]) async {
    if (_disposed) {
      throw StateError('Native avatar controller is disposed.');
    }
    await _transport.send(KundiNativeAvatarEnvelope.command(name, payload));
  }

  void _onRawEvent(Object? value) {
    try {
      _events.add(KundiNativeAvatarEvent.parse(value));
    } on Object catch (error) {
      _events.add(
        KundiNativeAvatarEvent(
          name: 'rendererError',
          payload: <String, Object?>{
            'code': 'invalid_event',
            'message': error.toString(),
          },
        ),
      );
    }
  }

  void _onTransportError(Object error, StackTrace stackTrace) {
    _events.add(
      KundiNativeAvatarEvent(
        name: 'rendererError',
        payload: <String, Object?>{
          'code': 'event_channel_error',
          'message': error.toString(),
        },
      ),
    );
  }
}
