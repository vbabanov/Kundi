import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'assistant_controller.dart';

final assistantVoiceLocaleResolverProvider =
    Provider<AssistantVoiceLocaleResolver>((ref) {
  return AssistantVoiceLocaleResolver(
    activeSessionLocale: () => ref
        .read(assistantControllerProvider)
        .valueOrNull
        ?.activeSession
        ?.locale,
    waitForAssistant: () => ref.read(assistantControllerProvider.future),
  );
});

enum AssistantVoiceLocaleSource {
  activeSession,
  ensuredSession,
  fallback,
}

final class AssistantVoiceLocaleResolution {
  const AssistantVoiceLocaleResolution({
    required this.locale,
    required this.source,
  });

  final String locale;
  final AssistantVoiceLocaleSource source;
}

/// Resolves the locale before microphone permission or recognition starts.
///
/// The current profile projection does not expose locale. The existing
/// Assistant initialization path is therefore the canonical source when no
/// active session is loaded: it reuses the controller's one in-flight Future
/// and creates at most the single session already required for voice send.
final class AssistantVoiceLocaleResolver {
  AssistantVoiceLocaleResolver({
    required String? Function() activeSessionLocale,
    required Future<AssistantViewState> Function() waitForAssistant,
  })  : _activeSessionLocale = activeSessionLocale,
        _waitForAssistant = waitForAssistant;

  static const fallbackLocale = 'ru-KZ';

  final String? Function() _activeSessionLocale;
  final Future<AssistantViewState> Function() _waitForAssistant;
  Future<AssistantVoiceLocaleResolution>? _inFlight;

  Future<AssistantVoiceLocaleResolution> resolve() {
    final active = _supported(_activeSessionLocale());
    if (active != null) {
      return Future<AssistantVoiceLocaleResolution>.value(
        AssistantVoiceLocaleResolution(
          locale: active,
          source: AssistantVoiceLocaleSource.activeSession,
        ),
      );
    }
    return _inFlight ??= _resolveFromAssistant().whenComplete(() {
      _inFlight = null;
    });
  }

  Future<AssistantVoiceLocaleResolution> _resolveFromAssistant() async {
    try {
      final view = await _waitForAssistant();
      final locale = _supported(view.activeSession?.locale);
      if (locale != null) {
        return AssistantVoiceLocaleResolution(
          locale: locale,
          source: AssistantVoiceLocaleSource.ensuredSession,
        );
      }
    } catch (_) {
      // Voice remains available through the documented Russian fallback.
    }
    return const AssistantVoiceLocaleResolution(
      locale: fallbackLocale,
      source: AssistantVoiceLocaleSource.fallback,
    );
  }

  static String? _supported(String? raw) {
    final locale = raw?.trim();
    if (locale == null || locale.isEmpty) return null;
    switch (locale.toLowerCase()) {
      case 'kk':
      case 'kk-kz':
        return 'kk-KZ';
      case 'ru':
      case 'ru-kz':
        return 'ru-KZ';
      case 'ru-ru':
        return 'ru-RU';
      default:
        return null;
    }
  }
}
