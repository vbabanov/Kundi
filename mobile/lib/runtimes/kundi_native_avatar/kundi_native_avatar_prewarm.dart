import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'kundi_native_avatar_feature.dart';

abstract final class KundiNativeAvatarPrewarm {
  static const MethodChannel _channel = MethodChannel(
    'kundi/native_avatar/prewarm',
  );
  static Future<Map<String, Object?>>? _inFlight;
  static Map<String, Object?>? _completed;

  static Future<Map<String, Object?>> run() => runWith(
        enabled: KundiNativeAvatarFeature.enabled,
        invoke: _invokeNative,
      );

  @visibleForTesting
  static Future<Map<String, Object?>> runWith({
    required bool enabled,
    required Future<Map<String, Object?>> Function() invoke,
  }) async {
    if (!enabled) {
      return const <String, Object?>{'status': 'disabled'};
    }
    final completed = _completed;
    if (completed != null) {
      return completed;
    }
    final pending = _inFlight;
    if (pending != null) {
      return pending;
    }

    final operation = invoke();
    _inFlight = operation;
    try {
      final result = await operation;
      if (result['status'] case 'cached' || 'alreadyCached' || 'unsupported') {
        _completed = result;
      }
      return result;
    } finally {
      if (identical(_inFlight, operation)) {
        _inFlight = null;
      }
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    _inFlight = null;
    _completed = null;
  }

  static bool isRuntimeReady(Map<String, Object?> result) =>
      result['eligible'] != false &&
      (result['status'] == 'cached' || result['status'] == 'alreadyCached');

  static Future<Map<String, Object?>> _invokeNative() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('prewarm');
      return result ?? const <String, Object?>{'status': 'noResult'};
    } on PlatformException catch (error) {
      return <String, Object?>{'status': 'failed', 'code': error.code};
    }
  }
}
