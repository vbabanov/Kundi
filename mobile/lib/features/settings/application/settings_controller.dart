import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_repository_impl.dart';
import '../domain/settings_entity.dart';
import '../domain/settings_repository.dart';

final appSettingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepositoryImpl();
});

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() {
    return ref.watch(appSettingsRepositoryProvider).load();
  }

  Future<void> setTheme(AppThemePreference theme) async {
    final current = state.valueOrNull ?? const AppSettings();
    if (current.theme == theme) {
      return;
    }
    await ref.read(appSettingsRepositoryProvider).saveTheme(theme);
    state = AsyncData(current.copyWith(theme: theme));
  }

  Future<void> setLanguage(AppLanguage language) async {
    final current = state.valueOrNull ?? const AppSettings();
    if (current.language == language) {
      return;
    }
    await ref.read(appSettingsRepositoryProvider).saveLanguage(language);
    state = AsyncData(current.copyWith(language: language));
  }
}
