import 'package:flutter/foundation.dart';

abstract final class KundiNativeAvatarFeature {
  static const bool compiledEnabled = bool.fromEnvironment(
    'ENABLE_KUNDI_HOME_REALTIME_AVATAR',
  );
  static const String _renderScaleValue = String.fromEnvironment(
    'KUNDI_HOME_AVATAR_RENDER_SCALE',
    defaultValue: '0.75',
  );
  static const String _passiveBurstIntervalMillisValue = String.fromEnvironment(
    'KUNDI_HOME_AVATAR_PASSIVE_BURST_INTERVAL_MS',
    defaultValue: '15000',
  );
  static const String _passiveBurstDurationMillisValue = String.fromEnvironment(
    'KUNDI_HOME_AVATAR_PASSIVE_BURST_DURATION_MS',
    defaultValue: '800',
  );

  static double get renderScale =>
      (double.tryParse(_renderScaleValue) ?? 0.75).clamp(0.5, 1.0);

  static int get passiveBurstIntervalMillis => normalizePassiveBurstInterval(
    int.tryParse(_passiveBurstIntervalMillisValue),
  );

  static int get passiveBurstDurationMillis => normalizePassiveBurstDuration(
    int.tryParse(_passiveBurstDurationMillisValue),
  );

  static bool get enabled => isEnabledFor(
    platform: defaultTargetPlatform,
    compiledEnabled: compiledEnabled,
  );

  @visibleForTesting
  static bool isEnabledFor({
    required TargetPlatform platform,
    required bool compiledEnabled,
  }) => platform == TargetPlatform.android && compiledEnabled;

  @visibleForTesting
  static int normalizePassiveBurstInterval(int? value) =>
      value != null && value >= 10000 && value <= 20000 ? value : 15000;

  @visibleForTesting
  static int normalizePassiveBurstDuration(int? value) =>
      value != null && value >= 300 && value <= 1500 ? value : 800;
}
