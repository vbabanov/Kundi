import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'runtimes/kundi_system_speech/kundi_voice_qa_telemetry.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  KundiVoiceQaTelemetry.event('telemetryBoot');
  runApp(const ProviderScope(child: KundiApp()));
}
