import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/auth/data/refresh_run_gate.dart';

void main() {
  test('coalesces rapid refresh triggers into single in-flight run', () async {
    final gate = RefreshRunGate<int>();
    var started = 0;
    var coalesced = 0;
    final blocker = Completer<void>();

    final first = gate.run(() async {
      started += 1;
      await blocker.future;
      return 7;
    });
    final second = gate.run(
      () async {
        started += 1;
        return 8;
      },
      onCoalesced: () => coalesced += 1,
    );

    expect(gate.isRunning, isTrue);
    expect(started, 1);
    expect(coalesced, 1);

    blocker.complete();

    expect(await first, 7);
    expect(await second, 7);
    expect(gate.isRunning, isFalse);
  });

  test('starts new refresh run after previous completes', () async {
    final gate = RefreshRunGate<int>();
    var started = 0;

    final first = await gate.run(() async {
      started += 1;
      return 1;
    });
    final second = await gate.run(() async {
      started += 1;
      return 2;
    });

    expect(first, 1);
    expect(second, 2);
    expect(started, 2);
  });

  test('coalesced callers observe one published refresh payload', () async {
    final gate = RefreshRunGate<Map<String, String>>();
    var started = 0;

    final first = gate.run(() async {
      started += 1;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return const {
        'refresh_status': 'success',
        'snapshot_at': '2026-04-01T10:00:00Z',
      };
    });
    final second = gate.run(() async {
      started += 1;
      return const {
        'refresh_status': 'success',
        'snapshot_at': 'should-not-publish',
      };
    });
    final third = gate.run(() async {
      started += 1;
      return const {
        'refresh_status': 'success',
        'snapshot_at': 'should-not-publish-2',
      };
    });

    final firstResult = await first;
    final secondResult = await second;
    final thirdResult = await third;

    expect(started, 1);
    expect(firstResult['snapshot_at'], '2026-04-01T10:00:00Z');
    expect(secondResult['snapshot_at'], firstResult['snapshot_at']);
    expect(thirdResult['snapshot_at'], firstResult['snapshot_at']);
  });
}
