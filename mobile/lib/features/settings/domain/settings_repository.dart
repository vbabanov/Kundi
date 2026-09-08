import 'settings_entity.dart';

abstract class SettingsRepository {
  Future<AppSettings> load();

  Future<void> saveTheme(AppThemePreference theme);

  Future<void> saveLanguage(AppLanguage language);
}
