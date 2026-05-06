import 'dart:async';

import 'package:flutter/services.dart';

import '../contracts/avatar_events.dart';
import '../contracts/avatar_response_package.dart';
import 'avatar_bridge.dart';

class MethodChannelAvatarBridge implements AvatarBridge {
  MethodChannelAvatarBridge({
    MethodChannel? commands,
    EventChannel? events,
  })  : _commands =
            commands ?? const MethodChannel('kundi/avatar_runtime/commands'),
        _events = events ?? const EventChannel('kundi/avatar_runtime/events');

  final MethodChannel _commands;
  final EventChannel _events;

  @override
  Stream<AvatarEvent> get events =>
      _events.receiveBroadcastStream().map(_mapEvent);

  @override
  Future<void> initializeAvatar() =>
      _commands.invokeMethod<void>('initializeAvatar');

  @override
  Future<void> showAvatar() => _commands.invokeMethod<void>('showAvatar');

  @override
  Future<void> hideAvatar() => _commands.invokeMethod<void>('hideAvatar');

  @override
  Future<void> startListening() =>
      _commands.invokeMethod<void>('startListening');

  @override
  Future<void> startThinking() => _commands.invokeMethod<void>('startThinking');

  @override
  Future<void> speak(AvatarResponsePackage responsePackage) {
    return _commands.invokeMethod<void>('speak', responsePackage.toJson());
  }

  @override
  Future<void> interrupt() => _commands.invokeMethod<void>('interrupt');

  @override
  Future<void> setEmotion(String emotion) =>
      _commands.invokeMethod<void>('setEmotion', {'emotion': emotion});

  @override
  Future<void> playGesture(String gesture) =>
      _commands.invokeMethod<void>('playGesture', {'gesture': gesture});

  @override
  Future<void> resetToIdle() => _commands.invokeMethod<void>('resetToIdle');

  AvatarEvent _mapEvent(dynamic raw) {
    if (raw is! Map) {
      return const AvatarEvent(
          type: AvatarEventType.error,
          payload: {'message': 'invalid event payload'});
    }
    final map = Map<String, dynamic>.from(raw);
    final event = (map['event'] ?? '').toString();
    final payload = map['payload'] is Map<String, dynamic>
        ? map['payload'] as Map<String, dynamic>
        : (map['payload'] is Map
            ? Map<String, dynamic>.from(map['payload'] as Map)
            : <String, dynamic>{});

    return AvatarEvent(type: _toEventType(event), payload: payload);
  }

  AvatarEventType _toEventType(String event) {
    switch (event) {
      case 'avatarReady':
        return AvatarEventType.avatarReady;
      case 'playbackStarted':
        return AvatarEventType.playbackStarted;
      case 'playbackCompleted':
        return AvatarEventType.playbackCompleted;
      case 'interrupted':
        return AvatarEventType.interrupted;
      default:
        return AvatarEventType.error;
    }
  }
}
