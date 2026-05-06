import 'dart:async';

import '../bridge/avatar_bridge.dart';
import '../contracts/avatar_events.dart';
import '../contracts/avatar_response_package.dart';

class AvatarFacade {
  AvatarFacade(this._bridge);

  final AvatarBridge _bridge;

  Stream<AvatarEvent> get events => _bridge.events;

  Future<void> initializeAvatar() => _bridge.initializeAvatar();

  Future<void> showAvatar() => _bridge.showAvatar();

  Future<void> hideAvatar() => _bridge.hideAvatar();

  Future<void> startListening() => _bridge.startListening();

  Future<void> startThinking() => _bridge.startThinking();

  Future<void> speak(AvatarResponsePackage responsePackage) =>
      _bridge.speak(responsePackage);

  Future<void> interrupt() => _bridge.interrupt();

  Future<void> setEmotion(String emotion) => _bridge.setEmotion(emotion);

  Future<void> playGesture(String gesture) => _bridge.playGesture(gesture);

  Future<void> resetToIdle() => _bridge.resetToIdle();
}
