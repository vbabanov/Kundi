import 'package:flutter/widgets.dart';

/// Canonical Home avatar composition shared by the Flutter slot and Filament.
///
/// The slot values preserve the accepted Home layout. Camera distance controls
/// screen-space height; root translation controls the accepted foot and center
/// anchors. The Texture itself is never scaled or translated after rendering.
abstract final class KundiHomeAvatarPlacement {
  static const double slotRight = -20;
  static const double slotTop = -12;
  static const double slotBottom = -95;
  static const double slotWidth = 235;

  static const double acceptedOverlapDepth = 95;
  static const double horizontalAnchorFraction = 0.565;
  static const double footAnchorFraction = 0.958;
  static const double targetScreenHeightFraction = 0.922;

  static const double cameraFovDegrees = 38;
  static const double cameraDistance = 3.14;
  static const double cameraEyeY = 0.02;
  static const double cameraTargetY = 0;
  static const double modelHalfExtent = 0.92;
  static const double modelOffsetX = 0.085;
  static const double modelOffsetY = 0.084;

  static const double heroRestNormalizedTime = 0;

  static const Duration loadingCrossfadeDuration = Duration(
    milliseconds: 90,
  );

  static const String loadingAssetPath =
      'assets/images/kundi/home/kundi_home_loading.webp';

  static const String fatalFallbackAssetPath =
      'assets/images/kundi/home/kundi_home.webp';

  static const Key loadingAssetKey = Key('kundi-home-avatar-loading-asset');

  static Map<String, Object> get rendererArguments => <String, Object>{
        'cameraFovDegrees': cameraFovDegrees,
        'cameraDistance': cameraDistance,
        'cameraEyeY': cameraEyeY,
        'cameraTargetY': cameraTargetY,
        'modelHalfExtent': modelHalfExtent,
        'modelOffsetX': modelOffsetX,
        'modelOffsetY': modelOffsetY,
        'heroRestNormalizedTime': heroRestNormalizedTime,
      };
}
