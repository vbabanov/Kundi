import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/settings/data/settings_repository_impl.dart';
import 'package:kundi_mobile/features/settings/domain/settings_entity.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('defaults to dark and Russian without stored preferences', () async {
    final repository = SettingsRepositoryImpl();

    final settings = await repository.load();

    expect(settings.theme, AppThemePreference.dark);
    expect(settings.language, AppLanguage.ru);
  });

  test('theme and language persist across repository recreation', () async {
    final firstInstance = SettingsRepositoryImpl();
    await firstInstance.saveTheme(AppThemePreference.light);
    await firstInstance.saveLanguage(AppLanguage.kk);

    final afterRestart = await SettingsRepositoryImpl().load();

    expect(afterRestart.theme, AppThemePreference.light);
    expect(afterRestart.language, AppLanguage.kk);
  });

  test('invalid stored values fall back safely', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app_settings.theme': 'system',
      'app_settings.language': 'en',
    });

    final settings = await SettingsRepositoryImpl().load();

    expect(settings.theme, AppThemePreference.dark);
    expect(settings.language, AppLanguage.ru);
  });
}
