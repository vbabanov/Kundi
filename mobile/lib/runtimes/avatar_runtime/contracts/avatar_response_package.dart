enum AvatarAudioStatus {
  ready,
  unavailable,
}

class AvatarViseme {
  const AvatarViseme({
    required this.offsetMs,
    required this.id,
    required this.weight,
  });

  final int offsetMs;
  final String id;
  final double weight;

  Map<String, dynamic> toJson() {
    return {
      'offset_ms': offsetMs,
      'id': id,
      'weight': weight,
    };
  }
}

class AvatarPedagogyFlags {
  const AvatarPedagogyFlags({
    required this.needsScaffold,
    required this.containsHint,
    required this.containsStepPlan,
    required this.safetyIntervention,
  });

  final bool needsScaffold;
  final bool containsHint;
  final bool containsStepPlan;
  final bool safetyIntervention;

  Map<String, dynamic> toJson() {
    return {
      'needs_scaffold': needsScaffold,
      'contains_hint': containsHint,
      'contains_step_plan': containsStepPlan,
      'safety_intervention': safetyIntervention,
    };
  }
}

class AvatarResponsePackage {
  const AvatarResponsePackage({
    required this.text,
    required this.audioUrl,
    required this.audioStatus,
    required this.visemes,
    required this.emotion,
    required this.gestureTags,
    required this.pedagogyFlags,
  });

  final String text;
  final String audioUrl;
  final AvatarAudioStatus audioStatus;
  final List<AvatarViseme> visemes;
  final String emotion;
  final List<String> gestureTags;
  final AvatarPedagogyFlags pedagogyFlags;

  bool get hasPlayableAudio =>
      audioStatus == AvatarAudioStatus.ready && audioUrl.trim().isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'audioUrl': audioUrl,
      'audioStatus': audioStatus.name,
      'visemes': visemes.map((item) => item.toJson()).toList(growable: false),
      'emotion': emotion,
      'gestureTags': gestureTags,
      'pedagogyFlags': pedagogyFlags.toJson(),
    };
  }
}
