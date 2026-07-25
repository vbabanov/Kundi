import '../domain/kundi_behavior_state.dart';

enum KundiVisualEmphasis { none, gentle, attention }

class KundiHomePresentation {
  const KundiHomePresentation({
    required this.assetPath,
    required this.title,
    required this.message,
    required this.semanticLabel,
    required this.visualEmphasis,
    required this.animationCueName,
  });

  final String assetPath;
  final String title;
  final String message;
  final String semanticLabel;
  final KundiVisualEmphasis visualEmphasis;
  final String animationCueName;
}

class KundiHomePresentationAdapter {
  const KundiHomePresentationAdapter();

  static const fallbackAssetPath = 'assets/images/kundi/home/kundi_home.webp';

  KundiHomePresentation adapt({
    required KundiBehaviorState state,
    required String neutralTitle,
    required String neutralMessage,
    required String neutralSemanticLabel,
  }) {
    if (!_cueMatchesState(state)) {
      return _neutral(
        title: neutralTitle,
        message: neutralMessage,
        semanticLabel: neutralSemanticLabel,
      );
    }

    switch (state.kind) {
      case KundiBehaviorKind.neutral:
        return _neutral(
          title: neutralTitle,
          message: neutralMessage,
          semanticLabel: neutralSemanticLabel,
        );
      case KundiBehaviorKind.celebrating:
        return _presentation(
          title: neutralTitle,
          message: 'Отличная работа!',
          semanticLabel: 'Kundi радуется успеху',
          emphasis: KundiVisualEmphasis.gentle,
          cueName: 'celebrate',
        );
      case KundiBehaviorKind.thinking:
        return _presentation(
          title: neutralTitle,
          message: 'Думаю…',
          semanticLabel: 'Kundi думает',
          emphasis: KundiVisualEmphasis.gentle,
          cueName: 'think',
        );
      case KundiBehaviorKind.speaking:
        return _presentation(
          title: neutralTitle,
          message: 'Ответ появится здесь позже.',
          semanticLabel: 'Kundi готовит ответ',
          emphasis: KundiVisualEmphasis.gentle,
          cueName: 'speak',
        );
      case KundiBehaviorKind.listening:
        return _presentation(
          title: neutralTitle,
          message: 'Я слушаю',
          semanticLabel: 'Kundi слушает',
          emphasis: KundiVisualEmphasis.gentle,
          cueName: 'listen',
        );
      case KundiBehaviorKind.warning:
        return _presentation(
          title: neutralTitle,
          message: 'Давай спокойно проверим, что требует внимания.',
          semanticLabel: 'Kundi предлагает проверить важное',
          emphasis: KundiVisualEmphasis.attention,
          cueName: 'warn',
        );
      case KundiBehaviorKind.error:
        return _presentation(
          title: neutralTitle,
          message: 'Что-то пошло не так. Попробуем ещё раз позже.',
          semanticLabel: 'Kundi временно недоступен',
          emphasis: KundiVisualEmphasis.attention,
          cueName: 'error',
        );
    }
  }

  KundiHomePresentation _neutral({
    required String title,
    required String message,
    required String semanticLabel,
  }) {
    return _presentation(
      title: title,
      message: message,
      semanticLabel: semanticLabel,
      emphasis: KundiVisualEmphasis.none,
      cueName: 'neutral',
    );
  }

  KundiHomePresentation _presentation({
    required String title,
    required String message,
    required String semanticLabel,
    required KundiVisualEmphasis emphasis,
    required String cueName,
  }) {
    return KundiHomePresentation(
      assetPath: fallbackAssetPath,
      title: title,
      message: message,
      semanticLabel: semanticLabel,
      visualEmphasis: emphasis,
      animationCueName: cueName,
    );
  }

  bool _cueMatchesState(KundiBehaviorState state) {
    switch (state.kind) {
      case KundiBehaviorKind.neutral:
        return state.presentationCue == KundiPresentationCue.neutral;
      case KundiBehaviorKind.celebrating:
        return state.presentationCue == KundiPresentationCue.celebrate;
      case KundiBehaviorKind.thinking:
        return state.presentationCue == KundiPresentationCue.think;
      case KundiBehaviorKind.speaking:
        return state.presentationCue == KundiPresentationCue.speak;
      case KundiBehaviorKind.listening:
        return state.presentationCue == KundiPresentationCue.listen;
      case KundiBehaviorKind.warning:
        return state.presentationCue == KundiPresentationCue.warn;
      case KundiBehaviorKind.error:
        return state.presentationCue == KundiPresentationCue.error;
    }
  }
}
