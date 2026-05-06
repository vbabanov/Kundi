import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/auth/data/typed_v2_runtime_gate.dart';

void main() {
  TypedV2GateRuntimeState feedRefreshes(
    TypedV2RuntimeGate gate,
    TypedV2GateRuntimeState state, {
    required int count,
    required String refreshStatus,
    int profileMs = 500,
    int resultsMs = 700,
    int overviewMs = 650,
    String fallbackReason = '',
  }) {
    var current = state;
    final now = DateTime.utc(2026, 4, 12, 12, 0, 0);
    for (var i = 0; i < count; i++) {
      final eval = gate.observe(
        state: current,
        stage: 'typed_read_refresh_result',
        outcome: refreshStatus,
        details: <String, dynamic>{
          'refresh_status': refreshStatus,
          'fallback_reason': fallbackReason,
          'profile_latency_ms': profileMs,
          'results_latency_ms': resultsMs,
          'overview_latency_ms': overviewMs,
        },
        now: now.add(Duration(minutes: i)),
      );
      current = eval!.state;
    }
    return current;
  }

  test('promote when rates and latency are green with enough samples', () {
    const gate = TypedV2RuntimeGate();
    var state = TypedV2GateRuntimeState.empty();
    state = feedRefreshes(
      gate,
      state,
      count: 20,
      refreshStatus: 'success',
      profileMs: 450,
      resultsMs: 600,
      overviewMs: 550,
    );

    final evaluation = gate.observe(
      state: state,
      stage: 'typed_read_parity_shadow',
      outcome: 'ok',
      details: const <String, dynamic>{},
      now: DateTime.utc(2026, 4, 12, 14, 0, 0),
    )!;

    expect(evaluation.decision, TypedV2GateDecision.promote);
    expect(evaluation.trigger, 'all_green_promote');
  });

  test('hold on insufficient sample window', () {
    const gate = TypedV2RuntimeGate();
    final state = feedRefreshes(
      gate,
      TypedV2GateRuntimeState.empty(),
      count: 4,
      refreshStatus: 'success',
    );

    final evaluation = gate.observe(
      state: state,
      stage: 'typed_read_refresh_result',
      outcome: 'success',
      details: const <String, dynamic>{
        'refresh_status': 'success',
      },
      now: DateTime.utc(2026, 4, 12, 15, 0, 0),
    )!;

    expect(evaluation.decision, TypedV2GateDecision.hold);
    expect(evaluation.trigger, 'insufficient_window');
  });

  test('rollback on snapshot inconsistency signal', () {
    const gate = TypedV2RuntimeGate();
    final state = feedRefreshes(
      gate,
      TypedV2GateRuntimeState.empty(),
      count: 20,
      refreshStatus: 'success',
    );

    final evaluation = gate.observe(
      state: state,
      stage: 'typed_read_v2_snapshot_inconsistency',
      outcome: 'failed',
      details: const <String, dynamic>{},
      now: DateTime.utc(2026, 4, 12, 15, 30, 0),
    )!;

    expect(evaluation.decision, TypedV2GateDecision.rollback);
    expect(evaluation.trigger, 'snapshot_inconsistency');
  });

  test('rollback on severe parity mismatch rate', () {
    const gate = TypedV2RuntimeGate();
    var state = feedRefreshes(
      gate,
      TypedV2GateRuntimeState.empty(),
      count: 24,
      refreshStatus: 'success',
    );

    final base = DateTime.utc(2026, 4, 12, 16, 0, 0);
    for (var i = 0; i < 100; i++) {
      final mismatchReason = i < 4 ? 'identity' : '';
      final outcome = mismatchReason.isEmpty ? 'ok' : 'mismatch';
      final eval = gate.observe(
        state: state,
        stage: 'typed_read_parity_shadow',
        outcome: outcome,
        details: <String, dynamic>{
          if (mismatchReason.isNotEmpty)
            'typed_read_parity_shadow_mismatch_reason': mismatchReason,
        },
        now: base.add(Duration(minutes: i)),
      )!;
      state = eval.state;
    }

    final evaluation = gate.observe(
      state: state,
      stage: 'typed_read_refresh_result',
      outcome: 'success',
      details: const <String, dynamic>{'refresh_status': 'success'},
      now: DateTime.utc(2026, 4, 12, 18, 0, 0),
    )!;

    expect(evaluation.decision, TypedV2GateDecision.rollback);
    expect(evaluation.trigger, 'parity_severe_rollback');
  });

  test('v1_grades_source_empty mismatch is non-blocking for stage gate', () {
    const gate = TypedV2RuntimeGate();
    var state = feedRefreshes(
      gate,
      TypedV2GateRuntimeState.empty(),
      count: 24,
      refreshStatus: 'success',
    );

    final evaluation = gate.observe(
      state: state,
      stage: 'typed_read_parity_shadow',
      outcome: 'mismatch',
      details: const <String, dynamic>{
        'typed_read_parity_shadow_mismatch_reason': 'v1_grades_source_empty',
      },
      now: DateTime.utc(2026, 4, 12, 16, 0, 0),
    )!;

    expect(evaluation.decision, TypedV2GateDecision.promote);
    expect(evaluation.trigger, 'all_green_promote');
    expect(evaluation.stats.parityMismatchRate, 0);
    expect(evaluation.stats.severeParityMismatchRate, 0);
  });

  test('serializes and restores gate runtime state', () {
    const gate = TypedV2RuntimeGate();
    var state = feedRefreshes(
      gate,
      TypedV2GateRuntimeState.empty(),
      count: 3,
      refreshStatus: 'success',
      profileMs: 100,
      resultsMs: 200,
      overviewMs: 150,
    );
    final parityEval = gate.observe(
      state: state,
      stage: 'typed_read_parity_shadow',
      outcome: 'mismatch',
      details: const <String, dynamic>{
        'typed_read_parity_shadow_mismatch_reason': 'v1_grades_source_empty',
      },
      now: DateTime.utc(2026, 4, 12, 17, 0, 0),
    )!;
    state = parityEval.state;

    final encoded = gate.serializeState(state);
    final restored = gate.deserializeState(encoded);

    expect(restored.refreshEvents.length, 3);
    expect(restored.parityEvents.length, 1);
    expect(
        restored.parityEvents.first.mismatchReason, 'v1_grades_source_empty');
  });

  test('trimState drops events outside rolling window', () {
    const gate = TypedV2RuntimeGate(
      thresholds: TypedV2GateThresholds(windowHours: 24),
    );
    final oldState = TypedV2GateRuntimeState(
      refreshEvents: <RefreshGateEvent>[
        RefreshGateEvent(
          timestamp: DateTime.utc(2026, 4, 10, 10, 0, 0),
          refreshStatus: 'success',
          fallbackReason: '',
          profileLatencyMs: 10,
          resultsLatencyMs: 10,
          overviewLatencyMs: 10,
        ),
      ],
      parityEvents: <ParityGateEvent>[
        ParityGateEvent(
          timestamp: DateTime.utc(2026, 4, 10, 10, 0, 0),
          outcome: 'ok',
          mismatchReason: '',
        ),
      ],
      snapshotInconsistencyEvents: <DateTime>[
        DateTime.utc(2026, 4, 10, 10, 0, 0),
      ],
    );

    final trimmed = gate.trimState(
      state: oldState,
      now: DateTime.utc(2026, 4, 12, 12, 0, 0),
    );
    expect(trimmed.refreshEvents, isEmpty);
    expect(trimmed.parityEvents, isEmpty);
    expect(trimmed.snapshotInconsistencyEvents, isEmpty);
  });
}
