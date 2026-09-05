import 'package:flutter/services.dart';

enum KundiTtsEventType {
  synthesisStarted,
  synthesisReady,
  playbackStarted,
  visemeDue,
  playbackCompleted,
  playbackCancelled,
  speechError,
}

final class KundiTtsEvent {
  const KundiTtsEvent(this.generation, this.type, [this.viseme = 'Neutral']);
  final int generation;
  final KundiTtsEventType type;
  final String viseme;
  factory KundiTtsEvent.parse(Object? raw) {
    final map = raw as Map;
    final type = KundiTtsEventType.values.byName(map['name'] as String);
    final payload = map['payload'] as Map?;
    final viseme = (payload?['viseme'] ?? 'Neutral') as String;
    if (!const {'Neutral', 'A', 'I', 'U', 'E', 'O'}.contains(viseme)) {
      throw const FormatException('Invalid speech event');
    }
    return KundiTtsEvent((map['generation'] as num).toInt(), type, viseme);
  }
}

abstract interface class KundiTtsTransport {
  Stream<KundiTtsEvent> get events;
  Future<bool> speak(
      int generation, String text, Map<String, dynamic> authorization);
  Future<void> cancel();
  Future<void> dispose();
}

final class MethodChannelKundiTtsTransport implements KundiTtsTransport {
  static const _methods = MethodChannel('kundi/tts/commands');
  static const _events = EventChannel('kundi/tts/events');
  @override
  Stream<KundiTtsEvent> get events =>
      _events.receiveBroadcastStream().map(KundiTtsEvent.parse);
  @override
  Future<bool> speak(
      int generation, String text, Map<String, dynamic> authorization) async {
    return await _methods.invokeMethod<bool>('speak', {
          ...authorization,
          'generation': generation,
          'text': text,
        }) ??
        false;
  }

  @override
  Future<void> cancel() => _methods.invokeMethod<void>('cancel');
  @override
  Future<void> dispose() => _methods.invokeMethod<void>('dispose');
}
