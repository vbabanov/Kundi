import 'dart:async';

import 'package:flutter/services.dart';

enum KundiSpeechPermission { granted, required, denied, permanentlyDenied }

final class KundiSystemSpeechEvent {
  const KundiSystemSpeechEvent(this.name, this.payload);

  final String name;
  final Map<String, dynamic> payload;

  String get requestId => (payload['requestId'] ?? '').toString();
}

abstract interface class KundiSystemSpeechTransport {
  Stream<KundiSystemSpeechEvent> get events;

  Future<bool> availability();
  Future<KundiSpeechPermission> permissionStatus();
  Future<KundiSpeechPermission> requestPermission();
  Future<void> openAppSettings();
  Future<bool> startListening({
    required String requestId,
    required String locale,
    bool partialResults = true,
    int maxResults = 3,
    bool qaTelemetryEnabled = false,
  });
  Future<void> stopListening();
  Future<void> cancelListening();
  Future<void> dispose();
}

final class MethodChannelKundiSystemSpeechTransport
    implements KundiSystemSpeechTransport {
  MethodChannelKundiSystemSpeechTransport({
    MethodChannel? commands,
    EventChannel? nativeEvents,
  })  : _commands = commands ?? const MethodChannel(_commandChannelName),
        _nativeEvents = nativeEvents ?? const EventChannel(_eventChannelName) {
    _events = _nativeEvents
        .receiveBroadcastStream()
        .map(_parseEvent)
        .asBroadcastStream();
  }

  static const int protocolVersion = 1;
  static const String _commandChannelName = 'kundi/system_speech/commands';
  static const String _eventChannelName = 'kundi/system_speech/events';

  final MethodChannel _commands;
  final EventChannel _nativeEvents;
  late final Stream<KundiSystemSpeechEvent> _events;

  @override
  Stream<KundiSystemSpeechEvent> get events => _events;

  @override
  Future<bool> availability() async {
    final response = await _command('availability');
    return response['available'] == true;
  }

  @override
  Future<KundiSpeechPermission> permissionStatus() async {
    final response = await _command('permissionStatus');
    return switch (response['permission']) {
      'granted' => KundiSpeechPermission.granted,
      'permanentlyDenied' => KundiSpeechPermission.permanentlyDenied,
      _ => KundiSpeechPermission.required,
    };
  }

  @override
  Future<KundiSpeechPermission> requestPermission() async {
    final pending = _next(
      _permissionEvents,
      timeout: const Duration(minutes: 2),
    );
    await _command('requestPermission');
    return _permissionFrom(await pending);
  }

  @override
  Future<void> openAppSettings() => _command('openAppSettings');

  @override
  Future<bool> startListening({
    required String requestId,
    required String locale,
    bool partialResults = true,
    int maxResults = 3,
    bool qaTelemetryEnabled = false,
  }) async {
    final response = await _command('startListening', <String, dynamic>{
      'requestId': requestId,
      'locale': locale,
      'partialResults': partialResults,
      'maxResults': maxResults,
      'qaTelemetryEnabled': qaTelemetryEnabled,
    });
    return response['accepted'] == true;
  }

  @override
  Future<void> stopListening() => _command('stopListening');

  @override
  Future<void> cancelListening() => _command('cancelListening');

  @override
  Future<void> dispose() => _command('dispose');

  Future<Map<String, dynamic>> _command(
    String name, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]) async {
    final raw =
        await _commands.invokeMethod<dynamic>('command', <String, dynamic>{
      'version': protocolVersion,
      'kind': 'command',
      'name': name,
      'payload': payload,
    });
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  Future<KundiSystemSpeechEvent> _next(
    Set<String> names, {
    Duration timeout = const Duration(seconds: 5),
  }) =>
      events.firstWhere((event) => names.contains(event.name)).timeout(timeout);

  static KundiSystemSpeechEvent _parseEvent(dynamic raw) {
    if (raw is! Map) {
      throw const FormatException('speech event must be a map');
    }
    final envelope = Map<String, dynamic>.from(raw);
    if (envelope['version'] != protocolVersion || envelope['kind'] != 'event') {
      throw const FormatException('unsupported speech event envelope');
    }
    final name = (envelope['name'] ?? '').toString();
    if (name.isEmpty) {
      throw const FormatException('speech event name is missing');
    }
    final payload = envelope['payload'] is Map
        ? Map<String, dynamic>.from(envelope['payload'] as Map)
        : <String, dynamic>{};
    return KundiSystemSpeechEvent(name, payload);
  }

  static KundiSpeechPermission _permissionFrom(KundiSystemSpeechEvent event) {
    return switch (event.name) {
      'permissionGranted' => KundiSpeechPermission.granted,
      'permissionPermanentlyDenied' => KundiSpeechPermission.permanentlyDenied,
      'permissionDenied' => KundiSpeechPermission.denied,
      _ => KundiSpeechPermission.required,
    };
  }

  static const Set<String> _permissionEvents = <String>{
    'permissionRequired',
    'permissionGranted',
    'permissionDenied',
    'permissionPermanentlyDenied',
  };
}
