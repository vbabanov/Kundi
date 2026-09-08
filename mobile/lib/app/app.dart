import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/assistant/application/kundi_tts_coordinator.dart';
import '../features/assistant/application/kundi_voice_assistant_coordinator.dart';
import '../features/auth/presentation/auth_page.dart';
import '../features/auth/presentation/main_shell_page.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/settings/application/settings_controller.dart';
import '../features/settings/domain/settings_entity.dart';
import '../l10n/generated/app_localizations.dart';
import '../runtimes/kundi_native_avatar/kundi_home_avatar_loading_frame.dart';
import '../runtimes/kundi_native_avatar/kundi_native_avatar_feature.dart';
import '../shared/theme/app_theme.dart';

class KundiApp extends ConsumerWidget {
  const KundiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(settingsControllerProvider, (previous, next) {
      final previousLanguage = previous?.valueOrNull?.language;
      final nextLanguage = next.valueOrNull?.language;
      if (previousLanguage == null ||
          nextLanguage == null ||
          previousLanguage == nextLanguage) {
        return;
      }
      unawaited(
        Future.wait<void>([
          ref.read(kundiVoiceAssistantCoordinatorProvider.notifier).cancel(),
          ref.read(kundiTtsCoordinatorProvider.notifier).cancel(),
        ]),
      );
    });
    final settings = ref.watch(settingsControllerProvider).valueOrNull ??
        const AppSettings();
    final themeMode = settings.theme == AppThemePreference.light
        ? ThemeMode.light
        : ThemeMode.dark;
    final authState = ref.watch(authControllerProvider);
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: Locale(settings.language.name),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: authState.when(
        data: (session) => session == null
            ? const AuthPage()
            : KundiHomeAvatarLoadingFrameGate(
                enabled: KundiNativeAvatarFeature.enabled,
                loading: const _StartupSplash(),
                builder: (context, frame) => MainShellPage(
                  avatarLoadingFrame: frame,
                ),
              ),
        loading: () => const _StartupSplash(),
        error: (_, __) => const AuthPage(),
      ),
    );
  }
}

class _StartupSplash extends StatelessWidget {
  const _StartupSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
