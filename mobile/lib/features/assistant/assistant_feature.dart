import 'package:flutter_riverpod/flutter_riverpod.dart';

const bool kundiAssistantEnabledByDefault = bool.fromEnvironment(
  'ENABLE_KUNDI_ASSISTANT',
  defaultValue: false,
);

final kundiAssistantEnabledProvider = Provider<bool>(
  (ref) => kundiAssistantEnabledByDefault,
);
