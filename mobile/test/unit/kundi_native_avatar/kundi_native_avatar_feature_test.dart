import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/runtimes/kundi_native_avatar/kundi_native_avatar_feature.dart';

void main() {
  test('compile-time feature flag defaults to false', () {
    expect(KundiNativeAvatarFeature.compiledEnabled, isFalse);
  });

  test('runtime requires Android and compile-time flag', () {
    expect(
      KundiNativeAvatarFeature.isEnabledFor(
        platform: TargetPlatform.android,
        compiledEnabled: true,
      ),
      isTrue,
    );
    expect(
      KundiNativeAvatarFeature.isEnabledFor(
        platform: TargetPlatform.android,
        compiledEnabled: false,
      ),
      isFalse,
    );
    expect(
      KundiNativeAvatarFeature.isEnabledFor(
        platform: TargetPlatform.iOS,
        compiledEnabled: true,
      ),
      isFalse,
    );
  });

  test('passive burst timing accepts only product bounds', () {
    expect(
      KundiNativeAvatarFeature.normalizePassiveBurstInterval(10000),
      10000,
    );
    expect(
      KundiNativeAvatarFeature.normalizePassiveBurstInterval(20000),
      20000,
    );
    expect(KundiNativeAvatarFeature.normalizePassiveBurstInterval(9999), 15000);
    expect(KundiNativeAvatarFeature.normalizePassiveBurstInterval(null), 15000);
    expect(KundiNativeAvatarFeature.normalizePassiveBurstDuration(300), 300);
    expect(KundiNativeAvatarFeature.normalizePassiveBurstDuration(1500), 1500);
    expect(KundiNativeAvatarFeature.normalizePassiveBurstDuration(1501), 800);
    expect(KundiNativeAvatarFeature.normalizePassiveBurstDuration(null), 800);
  });
}
