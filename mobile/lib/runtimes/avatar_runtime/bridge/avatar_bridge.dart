import '../contracts/avatar_events.dart';
import '../contracts/avatar_response_package.dart';

abstract class AvatarBridge {
  Stream<AvatarEvent> get events;

  Future<void> initializeAvatar();

  Future<void> showAvatar();

  Future<void> hideAvatar();

  Future<void> startListening();

  Future<void> startThinking();

  Future<void> speak(AvatarResponsePackage responsePackage);

  Future<void> interrupt();

  Future<void> setEmotion(String emotion);

  Future<void> playGesture(String gesture);

  Future<void> resetToIdle();
}
