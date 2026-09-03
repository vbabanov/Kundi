import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/runtimes/kundi_native_avatar/kundi_native_avatar_prewarm.dart';

void main() {
  setUp(KundiNativeAvatarPrewarm.resetForTesting);
  tearDown(KundiNativeAvatarPrewarm.resetForTesting);

  test('concurrent prewarm callers share one native load', () async {
    final completion = Completer<Map<String, Object?>>();
    var calls = 0;

    Future<Map<String, Object?>> invoke() {
      calls++;
      return completion.future;
    }

    final first = KundiNativeAvatarPrewarm.runWith(
      enabled: true,
      invoke: invoke,
    );
    final second = KundiNativeAvatarPrewarm.runWith(
      enabled: true,
      invoke: invoke,
    );
    completion.complete(<String, Object?>{'status': 'cached', 'bytes': 10});

    expect(await first, await second);
    expect(calls, 1);
  });

  test('successful prewarm is reused without another native call', () async {
    var calls = 0;

    Future<Map<String, Object?>> invoke() async {
      calls++;
      return <String, Object?>{'status': 'cached', 'bytes': 10};
    }

    await KundiNativeAvatarPrewarm.runWith(enabled: true, invoke: invoke);
    await KundiNativeAvatarPrewarm.runWith(enabled: true, invoke: invoke);

    expect(calls, 1);
  });

  test('failed prewarm can be retried', () async {
    var calls = 0;

    Future<Map<String, Object?>> invoke() async {
      calls++;
      return <String, Object?>{'status': 'failed'};
    }

    await KundiNativeAvatarPrewarm.runWith(enabled: true, invoke: invoke);
    await KundiNativeAvatarPrewarm.runWith(enabled: true, invoke: invoke);

    expect(calls, 2);
  });

  test('unsupported eligibility is cached and keeps WebP fallback', () async {
    var calls = 0;

    Future<Map<String, Object?>> invoke() async {
      calls++;
      return <String, Object?>{
        'status': 'unsupported',
        'eligible': false,
        'reasons': <String>['low_ram_device'],
      };
    }

    final first = await KundiNativeAvatarPrewarm.runWith(
      enabled: true,
      invoke: invoke,
    );
    final second = await KundiNativeAvatarPrewarm.runWith(
      enabled: true,
      invoke: invoke,
    );

    expect(KundiNativeAvatarPrewarm.isRuntimeReady(first), isFalse);
    expect(KundiNativeAvatarPrewarm.isRuntimeReady(second), isFalse);
    expect(calls, 1);
  });

  test('runtime is ready only after an eligible cached model', () {
    expect(
      KundiNativeAvatarPrewarm.isRuntimeReady(
        <String, Object?>{'status': 'cached', 'eligible': true},
      ),
      isTrue,
    );
    expect(
      KundiNativeAvatarPrewarm.isRuntimeReady(
        <String, Object?>{'status': 'failed', 'eligible': true},
      ),
      isFalse,
    );
  });
}
