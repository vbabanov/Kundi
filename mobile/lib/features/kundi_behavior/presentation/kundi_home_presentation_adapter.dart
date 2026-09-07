import '../domain/kundi_behavior_state.dart';
import '../../../runtimes/kundi_native_avatar/kundi_native_avatar_protocol.dart';

enum KundiVisualEmphasis { none, gentle, attention }

class KundiHomePresentation {
  const KundiHomePresentation({
    required this.assetPath,
    required this.title,
    required this.message,
    required this.semanticLabel,
    required this.visualEmphasis,
    required this.animationCueName,
    required this.facialExpression,
  });

  final String assetPath;
  final String title;
  final String message;
  final String semanticLabel;
  final KundiVisualEmphasis visualEmphasis;
  final String animationCueName;
  final KundiFacialExpression facialExpression;
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
          expression: const KundiFacialExpression(
            emotion: KundiNativeAvatarEmotion.joy,
            intensity: 0.52,
          ),
        );
      case KundiBehaviorKind.thinking:
        return _presentation(
          title: neutralTitle,
          message: 'Думаю…',
          semanticLabel: 'Kundi думает',
          emphasis: KundiVisualEmphasis.gentle,
          cueName: 'think',
          expression: const KundiFacialExpression(
            emotion: KundiNativeAvatarEmotion.surprised,
            intensity: 0.18,
          ),
        );
      case KundiBehaviorKind.speaking:
        return _presentation(
          title: neutralTitle,
          message: 'Ответ появится здесь позже.',
          semanticLabel: 'Kundi готовит ответ',
          emphasis: KundiVisualEmphasis.gentle,
          cueName: 'speak',
          expression: const KundiFacialExpression(
            emotion: KundiNativeAvatarEmotion.joy,
            intensity: 0.14,
          ),
        );
      case KundiBehaviorKind.listening:
        return _presentation(
          title: neutralTitle,
          message: 'Я слушаю',
          semanticLabel: 'Kundi слушает',
          emphasis: KundiVisualEmphasis.gentle,
          cueName: 'listen',
          expression: const KundiFacialExpression(
            emotion: KundiNativeAvatarEmotion.joy,
            intensity: 0.16,
          ),
        );
      case KundiBehaviorKind.warning:
        return _presentation(
          title: neutralTitle,
          message: 'Давай спокойно проверим, что требует внимания.',
          semanticLabel: 'Kundi предлагает проверить важное',
          emphasis: KundiVisualEmphasis.attention,
          cueName: 'warn',
          expression: const KundiFacialExpression(
            emotion: KundiNativeAvatarEmotion.sorrow,
            intensity: 0.22,
          ),
        );
      case KundiBehaviorKind.error:
        return _presentation(
          title: neutralTitle,
          message: 'Что-то пошло не так. Попробуем ещё раз позже.',
          semanticLabel: 'Kundi временно недоступен',
          emphasis: KundiVisualEmphasis.attention,
          cueName: 'error',
          expression: const KundiFacialExpression(
            emotion: KundiNativeAvatarEmotion.sorrow,
            intensity: 0.32,
          ),
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
      expression: const KundiFacialExpression.neutral(),
    );
  }

  KundiHomePresentation _presentation({
    required String title,
    required String message,
    required String semanticLabel,
    required KundiVisualEmphasis emphasis,
    required String cueName,
    required KundiFacialExpression expression,
  }) {
    return KundiHomePresentation(
      assetPath: fallbackAssetPath,
      title: title,
      message: message,
      semanticLabel: semanticLabel,
      visualEmphasis: emphasis,
      animationCueName: cueName,
      facialExpression: expression,
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
