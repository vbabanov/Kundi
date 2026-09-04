import 'package:flutter_riverpod/flutter_riverpod.dart';

const bool kundiAssistantEnabledByDefault = bool.fromEnvironment(
  'ENABLE_KUNDI_ASSISTANT',
  defaultValue: false,
);

const bool kundiVoiceInputEnabledByDefault = bool.fromEnvironment(
  'ENABLE_KUNDI_VOICE_INPUT',
  defaultValue: false,
);

final kundiAssistantEnabledProvider = Provider<bool>(
  (ref) => kundiAssistantEnabledByDefault,
);

final kundiVoiceInputEnabledProvider = Provider<bool>(
  (ref) => kundiVoiceInputEnabledByDefault,
);
