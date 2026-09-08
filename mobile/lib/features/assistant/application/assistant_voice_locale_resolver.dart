import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/application/settings_controller.dart';
import '../../settings/domain/settings_entity.dart';

final assistantVoiceLocaleResolverProvider =
    Provider<AssistantVoiceLocaleResolver>((ref) {
  return AssistantVoiceLocaleResolver(
    appLanguage: () async =>
        (await ref.read(settingsControllerProvider.future)).language,
  );
});

enum AssistantVoiceLocaleSource { appLocale }

final class AssistantVoiceLocaleResolution {
  const AssistantVoiceLocaleResolution({
    required this.locale,
    required this.source,
  });

  final String locale;
  final AssistantVoiceLocaleSource source;
}

/// Voice recognition follows the persisted application language only.
/// Assistant session metadata is deliberately not consulted because history
/// can outlive a language change.
final class AssistantVoiceLocaleResolver {
  const AssistantVoiceLocaleResolver({
    required Future<AppLanguage> Function() appLanguage,
  }) : _appLanguage = appLanguage;

  final Future<AppLanguage> Function() _appLanguage;

  Future<AssistantVoiceLocaleResolution> resolve() async {
    return AssistantVoiceLocaleResolution(
      locale: localeFor(await _appLanguage()),
      source: AssistantVoiceLocaleSource.appLocale,
    );
  }

  static String localeFor(AppLanguage language) {
    return switch (language) {
      AppLanguage.ru => 'ru-RU',
      AppLanguage.kk => 'kk-KZ',
    };
  }
}
