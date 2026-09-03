import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/runtimes/kundi_native_avatar/kundi_home_avatar_placement.dart';

void main() {
  test('accepted Home slot geometry is unchanged', () {
    expect(KundiHomeAvatarPlacement.slotRight, -20);
    expect(KundiHomeAvatarPlacement.slotTop, -12);
    expect(KundiHomeAvatarPlacement.slotBottom, -95);
    expect(KundiHomeAvatarPlacement.slotWidth, 235);
    expect(KundiHomeAvatarPlacement.acceptedOverlapDepth, 95);
  });

  test('renderer arguments come from the canonical placement config', () {
    expect(KundiHomeAvatarPlacement.rendererArguments, {
      'cameraFovDegrees': KundiHomeAvatarPlacement.cameraFovDegrees,
      'cameraDistance': KundiHomeAvatarPlacement.cameraDistance,
      'cameraEyeY': KundiHomeAvatarPlacement.cameraEyeY,
      'cameraTargetY': KundiHomeAvatarPlacement.cameraTargetY,
      'modelHalfExtent': KundiHomeAvatarPlacement.modelHalfExtent,
      'modelOffsetX': KundiHomeAvatarPlacement.modelOffsetX,
      'modelOffsetY': KundiHomeAvatarPlacement.modelOffsetY,
      'heroRestNormalizedTime': KundiHomeAvatarPlacement.heroRestNormalizedTime,
    });
  });
}
