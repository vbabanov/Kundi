enum AppThemePreference { dark, light }

enum AppLanguage { ru, kk }

class AppSettings {
  const AppSettings({
    this.theme = AppThemePreference.dark,
    this.language = AppLanguage.ru,
  });

  final AppThemePreference theme;
  final AppLanguage language;

  AppSettings copyWith({
    AppThemePreference? theme,
    AppLanguage? language,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      language: language ?? this.language,
    );
  }
}
