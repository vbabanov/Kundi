import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/assistant/application/assistant_voice_locale_resolver.dart';
import 'package:kundi_mobile/features/settings/domain/settings_entity.dart';

void main() {
  test('Russian app locale resolves exact recognition locale', () async {
    final resolver = AssistantVoiceLocaleResolver(
      appLanguage: () async => AppLanguage.ru,
    );

    final result = await resolver.resolve();

    expect(result.locale, 'ru-RU');
    expect(result.source, AssistantVoiceLocaleSource.appLocale);
  });

  test('Kazakh app locale resolves exact recognition locale', () async {
    final resolver = AssistantVoiceLocaleResolver(
      appLanguage: () async => AppLanguage.kk,
    );

    final result = await resolver.resolve();

    expect(result.locale, 'kk-KZ');
    expect(result.source, AssistantVoiceLocaleSource.appLocale);
  });

  test('a language change affects the next voice turn', () async {
    var language = AppLanguage.ru;
    final resolver = AssistantVoiceLocaleResolver(
      appLanguage: () async => language,
    );

    expect((await resolver.resolve()).locale, 'ru-RU');
    language = AppLanguage.kk;
    expect((await resolver.resolve()).locale, 'kk-KZ');
  });
}
