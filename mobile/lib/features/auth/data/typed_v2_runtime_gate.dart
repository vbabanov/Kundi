enum TypedV2GateDecision {
  promote,
  hold,
  rollback,
}

class TypedV2GateThresholds {
  const TypedV2GateThresholds({
    this.windowHours = 24,
    this.minRefreshSamplesForPromote = 20,
    this.failedRatePromoteMax = 0.01,
    this.failedRateHoldMax = 0.03,
    this.failedRateRollbackMin = 0.08,
    this.degradedRatePromoteMax = 0.03,
    this.degradedRateHoldMax = 0.07,
    this.degradedRateRollbackMin = 0.20,
    this.parityMismatchRatePromoteMax = 0.05,
    this.parityMismatchRateHoldMax = 0.10,
    this.severeParityMismatchRollbackMin = 0.03,
    this.profileP95PromoteMaxMs = 1200,
    this.resultsP95PromoteMaxMs = 1800,
    this.overviewP95PromoteMaxMs = 1400,
    this.profileP95HoldMaxMs = 1800,
    this.resultsP95HoldMaxMs = 2500,
    this.overviewP95HoldMaxMs = 2000,
  });

  final int windowHours;
  final int minRefreshSamplesForPromote;
  final double failedRatePromoteMax;
  final double failedRateHoldMax;
  final double failedRateRollbackMin;
  final double degradedRatePromoteMax;
  final double degradedRateHoldMax;
  final double degradedRateRollbackMin;
  final double parityMismatchRatePromoteMax;
  final double parityMismatchRateHoldMax;
  final double severeParityMismatchRollbackMin;
  final int profileP95PromoteMaxMs;
  final int resultsP95PromoteMaxMs;
  final int overviewP95PromoteMaxMs;
  final int profileP95HoldMaxMs;
  final int resultsP95HoldMaxMs;
  final int overviewP95HoldMaxMs;
}

class TypedV2GateRuntimeState {
  const TypedV2GateRuntimeState({
    required this.refreshEvents,
    required this.parityEvents,
    required this.snapshotInconsistencyEvents,
  });

  factory TypedV2GateRuntimeState.empty() {
    return const TypedV2GateRuntimeState(
      refreshEvents: <RefreshGateEvent>[],
      parityEvents: <ParityGateEvent>[],
      snapshotInconsistencyEvents: <DateTime>[],
    );
  }

  final List<RefreshGateEvent> refreshEvents;
  final List<ParityGateEvent> parityEvents;
  final List<DateTime> snapshotInconsistencyEvents;
}

class TypedV2GateEvaluation {
  const TypedV2GateEvaluation({
    required this.state,
    required this.decision,
    required this.trigger,
    required this.stats,
  });

  final TypedV2GateRuntimeState state;
  final TypedV2GateDecision decision;
  final String trigger;
  final TypedV2GateStats stats;
}

class TypedV2GateStats {
  const TypedV2GateStats({
    required this.samples,
    required this.failedRate,
    required this.degradedRate,
    required this.fallbackRate,
    required this.parityMismatchRate,
    required this.severeParityMismatchRate,
    required this.snapshotInconsistencyCount,
    required this.profileP95LatencyMs,
    required this.resultsP95LatencyMs,
    required this.overviewP95LatencyMs,
  });

  final int samples;
  final double failedRate;
  final double degradedRate;
  final double fallbackRate;
  final double parityMismatchRate;
  final double severeParityMismatchRate;
  final int snapshotInconsistencyCount;
  final int profileP95LatencyMs;
  final int resultsP95LatencyMs;
  final int overviewP95LatencyMs;
}

class TypedV2RuntimeGate {
  const TypedV2RuntimeGate({
    this.thresholds = const TypedV2GateThresholds(),
  });

  final TypedV2GateThresholds thresholds;

  TypedV2GateRuntimeState trimState({
    required TypedV2GateRuntimeState state,
    required DateTime now,
  }) {
    return _trim(state, now);
  }

  Map<String, dynamic> serializeState(TypedV2GateRuntimeState state) {
    return <String, dynamic>{
      'refresh_events': state.refreshEvents
          .map((item) => <String, dynamic>{
                'ts': item.timestamp.toUtc().toIso8601String(),
                'refresh_status': item.refreshStatus,
                'fallback_reason': item.fallbackReason,
                'profile_latency_ms': item.profileLatencyMs,
                'results_latency_ms': item.resultsLatencyMs,
                'overview_latency_ms': item.overviewLatencyMs,
              })
          .toList(growable: false),
      'parity_events': state.parityEvents
          .map((item) => <String, dynamic>{
                'ts': item.timestamp.toUtc().toIso8601String(),
                'outcome': item.outcome,
                'mismatch_reason': item.mismatchReason,
              })
          .toList(growable: false),
      'snapshot_inconsistency_events': state.snapshotInconsistencyEvents
          .map((item) => item.toUtc().toIso8601String())
          .toList(growable: false),
    };
  }

  TypedV2GateRuntimeState deserializeState(
    Map<String, dynamic>? raw,
  ) {
    if (raw == null || raw.isEmpty) {
      return TypedV2GateRuntimeState.empty();
    }
    final refresh = <RefreshGateEvent>[];
    for (final item in _asList(raw['refresh_events'])) {
      if (item is! Map) {
        continue;
      }
      final row = Map<String, dynamic>.from(item);
      final ts = DateTime.tryParse(_asPlainString(row['ts']));
      if (ts == null) {
        continue;
      }
      refresh.add(
        RefreshGateEvent(
          timestamp: ts.toUtc(),
          refreshStatus: _asString(row['refresh_status']),
          fallbackReason: _asString(row['fallback_reason']),
          profileLatencyMs: _asInt(row['profile_latency_ms']),
          resultsLatencyMs: _asInt(row['results_latency_ms']),
          overviewLatencyMs: _asInt(row['overview_latency_ms']),
        ),
      );
    }

    final parity = <ParityGateEvent>[];
    for (final item in _asList(raw['parity_events'])) {
      if (item is! Map) {
        continue;
      }
      final row = Map<String, dynamic>.from(item);
      final ts = DateTime.tryParse(_asPlainString(row['ts']));
      if (ts == null) {
        continue;
      }
      parity.add(
        ParityGateEvent(
          timestamp: ts.toUtc(),
          outcome: _asString(row['outcome']),
          mismatchReason: _asString(row['mismatch_reason']),
        ),
      );
    }

    final inconsistencies = <DateTime>[];
    for (final item in _asList(raw['snapshot_inconsistency_events'])) {
      final ts = DateTime.tryParse(_asPlainString(item));
      if (ts == null) {
        continue;
      }
      inconsistencies.add(ts.toUtc());
    }

    return TypedV2GateRuntimeState(
      refreshEvents: refresh,
      parityEvents: parity,
      snapshotInconsistencyEvents: inconsistencies,
    );
  }

  TypedV2GateEvaluation? observe({
    required TypedV2GateRuntimeState state,
    required String stage,
    required String outcome,
    required Map<String, dynamic> details,
    required DateTime now,
  }) {
    if (!_isGateSignalStage(stage)) {
      return null;
    }

    final updated = _appendEvent(
      state: state,
      stage: stage,
      outcome: outcome,
      details: details,
      now: now,
    );
    final trimmed = _trim(updated, now);
    final stats = _buildStats(trimmed);
    final decision = _evaluate(stats);
    final trigger = _triggerFor(stats, decision);
    return TypedV2GateEvaluation(
      state: trimmed,
      decision: decision,
      trigger: trigger,
      stats: stats,
    );
  }

  bool _isGateSignalStage(String stage) {
    return stage == 'typed_read_refresh_result' ||
        stage == 'typed_read_parity_shadow' ||
        stage == 'typed_read_v2_snapshot_inconsistency';
  }

  TypedV2GateRuntimeState _appendEvent({
    required TypedV2GateRuntimeState state,
    required String stage,
    required String outcome,
    required Map<String, dynamic> details,
    required DateTime now,
  }) {
    var refresh = state.refreshEvents;
    var parity = state.parityEvents;
    var inconsistencies = state.snapshotInconsistencyEvents;

    if (stage == 'typed_read_refresh_result') {
      refresh = <RefreshGateEvent>[
        ...refresh,
        RefreshGateEvent(
          timestamp: now,
          refreshStatus: _asString(details['refresh_status']),
          fallbackReason: _asString(details['fallback_reason']),
          profileLatencyMs: _asInt(details['profile_latency_ms']),
          resultsLatencyMs: _asInt(details['results_latency_ms']),
          overviewLatencyMs: _asInt(details['overview_latency_ms']),
        ),
      ];
    } else if (stage == 'typed_read_parity_shadow') {
      parity = <ParityGateEvent>[
        ...parity,
        ParityGateEvent(
          timestamp: now,
          outcome: outcome,
          mismatchReason:
              _asString(details['typed_read_parity_shadow_mismatch_reason']),
        ),
      ];
    } else if (stage == 'typed_read_v2_snapshot_inconsistency') {
      inconsistencies = <DateTime>[...inconsistencies, now];
    }

    return TypedV2GateRuntimeState(
      refreshEvents: refresh,
      parityEvents: parity,
      snapshotInconsistencyEvents: inconsistencies,
    );
  }

  TypedV2GateRuntimeState _trim(TypedV2GateRuntimeState state, DateTime now) {
    final cutoff = now.subtract(Duration(hours: thresholds.windowHours));
    return TypedV2GateRuntimeState(
      refreshEvents: state.refreshEvents
          .where((item) => !item.timestamp.isBefore(cutoff))
          .toList(growable: false),
      parityEvents: state.parityEvents
          .where((item) => !item.timestamp.isBefore(cutoff))
          .toList(growable: false),
      snapshotInconsistencyEvents: state.snapshotInconsistencyEvents
          .where((item) => !item.isBefore(cutoff))
          .toList(growable: false),
    );
  }

  TypedV2GateStats _buildStats(TypedV2GateRuntimeState state) {
    final samples = state.refreshEvents.length;
    final failed = state.refreshEvents
        .where((item) => item.refreshStatus == 'failed')
        .length;
    final degraded = state.refreshEvents
        .where((item) => item.refreshStatus == 'degraded')
        .length;
    final fallback = state.refreshEvents
        .where((item) => item.fallbackReason.isNotEmpty)
        .length;

    final paritySamples = state.parityEvents.length;
    final parityMismatch =
        state.parityEvents.where(_isBlockingParityMismatch).length;
    final severeParityMismatch = state.parityEvents.where((item) {
      return item.mismatchReason == 'identity' ||
          item.mismatchReason == 'mixed';
    }).length;

    return TypedV2GateStats(
      samples: samples,
      failedRate: _ratio(failed, samples),
      degradedRate: _ratio(degraded, samples),
      fallbackRate: _ratio(fallback, samples),
      parityMismatchRate: _ratio(parityMismatch, paritySamples),
      severeParityMismatchRate: _ratio(severeParityMismatch, paritySamples),
      snapshotInconsistencyCount: state.snapshotInconsistencyEvents.length,
      profileP95LatencyMs:
          _p95(state.refreshEvents.map((item) => item.profileLatencyMs)),
      resultsP95LatencyMs:
          _p95(state.refreshEvents.map((item) => item.resultsLatencyMs)),
      overviewP95LatencyMs:
          _p95(state.refreshEvents.map((item) => item.overviewLatencyMs)),
    );
  }

  TypedV2GateDecision _evaluate(TypedV2GateStats stats) {
    if (stats.snapshotInconsistencyCount > 0) {
      return TypedV2GateDecision.rollback;
    }
    if (stats.failedRate >= thresholds.failedRateRollbackMin) {
      return TypedV2GateDecision.rollback;
    }
    if (stats.degradedRate >= thresholds.degradedRateRollbackMin) {
      return TypedV2GateDecision.rollback;
    }
    if (stats.severeParityMismatchRate >=
        thresholds.severeParityMismatchRollbackMin) {
      return TypedV2GateDecision.rollback;
    }

    if (stats.samples < thresholds.minRefreshSamplesForPromote) {
      return TypedV2GateDecision.hold;
    }
    if (stats.failedRate > thresholds.failedRateHoldMax ||
        stats.degradedRate > thresholds.degradedRateHoldMax ||
        stats.parityMismatchRate > thresholds.parityMismatchRateHoldMax ||
        stats.profileP95LatencyMs > thresholds.profileP95HoldMaxMs ||
        stats.resultsP95LatencyMs > thresholds.resultsP95HoldMaxMs ||
        stats.overviewP95LatencyMs > thresholds.overviewP95HoldMaxMs) {
      return TypedV2GateDecision.hold;
    }

    if (stats.failedRate <= thresholds.failedRatePromoteMax &&
        stats.degradedRate <= thresholds.degradedRatePromoteMax &&
        stats.parityMismatchRate <= thresholds.parityMismatchRatePromoteMax &&
        stats.profileP95LatencyMs <= thresholds.profileP95PromoteMaxMs &&
        stats.resultsP95LatencyMs <= thresholds.resultsP95PromoteMaxMs &&
        stats.overviewP95LatencyMs <= thresholds.overviewP95PromoteMaxMs) {
      return TypedV2GateDecision.promote;
    }

    return TypedV2GateDecision.hold;
  }

  String _triggerFor(TypedV2GateStats stats, TypedV2GateDecision decision) {
    if (decision == TypedV2GateDecision.rollback) {
      if (stats.snapshotInconsistencyCount > 0) {
        return 'snapshot_inconsistency';
      }
      if (stats.failedRate >= thresholds.failedRateRollbackMin) {
        return 'failed_rate_rollback';
      }
      if (stats.degradedRate >= thresholds.degradedRateRollbackMin) {
        return 'degraded_rate_rollback';
      }
      return 'parity_severe_rollback';
    }
    if (decision == TypedV2GateDecision.hold) {
      if (stats.samples < thresholds.minRefreshSamplesForPromote) {
        return 'insufficient_window';
      }
      if (stats.failedRate > thresholds.failedRateHoldMax) {
        return 'failed_rate_hold';
      }
      if (stats.degradedRate > thresholds.degradedRateHoldMax) {
        return 'degraded_rate_hold';
      }
      if (stats.parityMismatchRate > thresholds.parityMismatchRateHoldMax) {
        return 'parity_rate_hold';
      }
      if (stats.profileP95LatencyMs > thresholds.profileP95HoldMaxMs ||
          stats.resultsP95LatencyMs > thresholds.resultsP95HoldMaxMs ||
          stats.overviewP95LatencyMs > thresholds.overviewP95HoldMaxMs) {
        return 'latency_hold';
      }
      return 'warn_band_hold';
    }
    return 'all_green_promote';
  }

  static String _asString(Object? value) {
    return (value ?? '').toString().trim().toLowerCase();
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse((value ?? '').toString());
  }

  static double _ratio(int numerator, int denominator) {
    if (denominator <= 0) {
      return 0;
    }
    return numerator / denominator;
  }

  static int _p95(Iterable<int?> values) {
    final filtered = values.whereType<int>().where((item) => item >= 0).toList()
      ..sort();
    if (filtered.isEmpty) {
      return 0;
    }
    final rawIndex = (filtered.length * 0.95).ceil() - 1;
    final index = rawIndex.clamp(0, filtered.length - 1);
    return filtered[index];
  }

  static bool _isBlockingParityMismatch(ParityGateEvent item) {
    if (item.outcome != 'mismatch') {
      return false;
    }
    return item.mismatchReason != 'v1_grades_source_empty';
  }

  static List<dynamic> _asList(Object? value) {
    if (value is List) {
      return List<dynamic>.from(value);
    }
    return const <dynamic>[];
  }

  static String _asPlainString(Object? value) {
    return (value ?? '').toString().trim();
  }
}

class RefreshGateEvent {
  const RefreshGateEvent({
    required this.timestamp,
    required this.refreshStatus,
    required this.fallbackReason,
    required this.profileLatencyMs,
    required this.resultsLatencyMs,
    required this.overviewLatencyMs,
  });

  final DateTime timestamp;
  final String refreshStatus;
  final String fallbackReason;
  final int? profileLatencyMs;
  final int? resultsLatencyMs;
  final int? overviewLatencyMs;
}

class ParityGateEvent {
  const ParityGateEvent({
    required this.timestamp,
    required this.outcome,
    required this.mismatchReason,
  });

  final DateTime timestamp;
  final String outcome;
  final String mismatchReason;
}
