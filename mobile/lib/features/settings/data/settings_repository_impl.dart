import 'package:shared_preferences/shared_preferences.dart';

import '../domain/settings_entity.dart';
import '../domain/settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl({
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  static const _themeKey = 'app_settings.theme';
  static const _languageKey = 'app_settings.language';

  final Future<SharedPreferences> Function() _preferences;

  @override
  Future<AppSettings> load() async {
    final preferences = await _preferences();
    return AppSettings(
      theme: _themeFromStorage(preferences.getString(_themeKey)),
      language: _languageFromStorage(preferences.getString(_languageKey)),
    );
  }

  @override
  Future<void> saveTheme(AppThemePreference theme) async {
    final preferences = await _preferences();
    final saved = await preferences.setString(_themeKey, theme.name);
    if (!saved) {
      throw StateError('Unable to persist app theme.');
    }
  }

  @override
  Future<void> saveLanguage(AppLanguage language) async {
    final preferences = await _preferences();
    final saved = await preferences.setString(_languageKey, language.name);
    if (!saved) {
      throw StateError('Unable to persist app language.');
    }
  }

  static AppThemePreference _themeFromStorage(String? raw) {
    return switch (raw) {
      'light' => AppThemePreference.light,
      _ => AppThemePreference.dark,
    };
  }

  static AppLanguage _languageFromStorage(String? raw) {
    return switch (raw) {
      'kk' => AppLanguage.kk,
      _ => AppLanguage.ru,
    };
  }
}
