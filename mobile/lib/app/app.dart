import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/presentation/auth_page.dart';
import '../features/auth/presentation/main_shell_page.dart';
import '../features/auth/application/auth_controller.dart';
import '../shared/providers/providers.dart';
import '../shared/theme/app_theme.dart';

class KundiApp extends ConsumerWidget {
  const KundiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider);
    final authState = ref.watch(authControllerProvider);
    return MaterialApp(
      title: 'Kundi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: authState.when(
        data: (session) =>
            session == null ? const AuthPage() : const MainShellPage(),
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
