enum KundiNativeAvatarEmotion {
  neutral('Neutral'),
  joy('Joy'),
  fun('Fun'),
  sorrow('Sorrow'),
  surprised('Surprised'),
  angry('Angry');

  const KundiNativeAvatarEmotion(this.wireName);
  final String wireName;
}

KundiNativeAvatarEmotion kundiNativeAvatarEmotionFromWire(String raw) {
  final normalized = raw.trim().toLowerCase();
  return KundiNativeAvatarEmotion.values.firstWhere(
    (emotion) => emotion.wireName.toLowerCase() == normalized,
    orElse: () => KundiNativeAvatarEmotion.neutral,
  );
}

final class KundiFacialExpression {
  const KundiFacialExpression({
    required this.emotion,
    required this.intensity,
  }) : assert(intensity >= 0 && intensity <= 1);

  const KundiFacialExpression.neutral()
      : emotion = KundiNativeAvatarEmotion.neutral,
        intensity = 1;

  factory KundiFacialExpression.fromApi({
    required String emotion,
    required double intensity,
  }) {
    final safeIntensity =
        intensity.isFinite ? intensity.clamp(0, 1).toDouble() : 1.0;
    return KundiFacialExpression(
      emotion: kundiNativeAvatarEmotionFromWire(emotion),
      intensity: safeIntensity,
    );
  }

  final KundiNativeAvatarEmotion emotion;
  final double intensity;
}

enum KundiNativeAvatarViseme {
  neutral('Neutral'),
  a('A'),
  i('I'),
  u('U'),
  e('E'),
  o('O');

  const KundiNativeAvatarViseme(this.wireName);
  final String wireName;
}

final class KundiNativeAvatarEnvelope {
  const KundiNativeAvatarEnvelope._();

  static const int version = 1;

  static Map<String, Object> command(
    String name, [
    Map<String, Object> payload = const {},
  ]) =>
      <String, Object>{
        'version': version,
        'kind': 'command',
        'name': name,
        'payload': payload,
      };
}

final class KundiNativeAvatarEvent {
  const KundiNativeAvatarEvent({required this.name, required this.payload});

  final String name;
  final Map<String, Object?> payload;

  static KundiNativeAvatarEvent parse(Object? value) {
    if (value is! Map) {
      throw const FormatException('Native avatar event must be a map.');
    }
    if (value['version'] != KundiNativeAvatarEnvelope.version ||
        value['kind'] != 'event' ||
        value['name'] is! String) {
      throw const FormatException('Unsupported native avatar event.');
    }
    final rawPayload = value['payload'];
    if (rawPayload is! Map) {
      throw const FormatException('Native avatar event payload must be a map.');
    }
    return KundiNativeAvatarEvent(
      name: value['name']! as String,
      payload: Map<String, Object?>.from(rawPayload),
    );
  }
}
