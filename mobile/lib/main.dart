import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/observability/crash_reporting.dart';
import 'runtimes/kundi_system_speech/kundi_voice_qa_telemetry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  KundiVoiceQaTelemetry.event('telemetryBoot');
  await KundiCrashReporting.run(
    () => runApp(const ProviderScope(child: KundiApp())),
  );
}
