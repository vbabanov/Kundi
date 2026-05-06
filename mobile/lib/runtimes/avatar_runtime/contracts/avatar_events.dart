enum AvatarEventType {
  avatarReady,
  playbackStarted,
  playbackCompleted,
  interrupted,
  error,
}

class AvatarEvent {
  const AvatarEvent({
    required this.type,
    this.payload = const <String, dynamic>{},
  });

  final AvatarEventType type;
  final Map<String, dynamic> payload;
}
