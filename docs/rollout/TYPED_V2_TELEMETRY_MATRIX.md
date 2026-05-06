# Typed V2 Telemetry Matrix

## Core Events
1. `typed_read_refresh_start`
2. `typed_read_refresh_result`
3. `typed_read_v2_degraded_refresh`
4. `typed_read_v2_failed`
5. `typed_read_parity_shadow`
6. `typed_read_v2_snapshot_inconsistency` (must be zero in healthy rollout)
7. `typed_read_stage_gate_check`

## Required Fields by Event

### `typed_read_refresh_start`
- `read_mode`
- `trace_id`
- `window_from`
- `window_to`

### `typed_read_refresh_result`
- `read_mode`
- `refresh_status`
- `provider`
- `window_key`
- `snapshot_at`
- `rows_written`
- `rows_deleted`
- `lessons_count`
- `results_count`
- `aggregates_count`
- `attendance_count`
- `trace_id`
- `last_refresh_mode`
- optional:
  - `fallback_reason`
  - `profile_latency_ms`
  - `results_latency_ms`
  - `overview_latency_ms`

### `typed_read_v2_degraded_refresh`
- `fallback_reason`
- `trace_id`

### `typed_read_v2_failed`
- `fallback_reason`
- `trace_id`
- sanitized `error`

### `typed_read_parity_shadow`
- `outcome` (`ok|mismatch|failed`)
- `count_match`
- `identity_match`
- `mood_match`
- `aggregate_match`
- `typed_read_parity_shadow_mismatch_reason` (`count|identity|mood|aggregate|mixed`)
- `mood_mismatch`
- `identity_mismatch`
- `aggregate_mismatch`
- `window_key`
- `snapshot_at`
- `trace_id`

### `typed_read_stage_gate_check`
- `outcome` (`promote|hold|rollback`)
- `gate_trigger`
- `samples`
- `failed_rate`
- `degraded_rate`
- `fallback_rate`
- `parity_mismatch_rate`
- `severe_parity_mismatch_rate`
- `snapshot_inconsistency_count`
- `profile_p95_latency_ms`
- `results_p95_latency_ms`
- `overview_p95_latency_ms`

## Dashboard Panels (Minimum)
1. Refresh outcome rates:
   - success/degraded/failed over time
2. Degraded and failed absolute counts
3. Parity mismatch rate + reason distribution
   - `mood_mismatch`
   - `identity_mismatch`
   - `aggregate_mismatch`
4. Snapshot inconsistency count (must remain zero)
5. Rows written/deleted trend
6. Data volume trend:
   - results_count
   - aggregates_count
   - attendance_count
7. Endpoint latency trend:
   - profile latency
   - results latency
   - overview latency
8. Runtime gate decision trend:
   - `typed_read_stage_gate_check` outcome over time
   - trigger distribution (`gate_trigger`)

## Gate Signals Mapping
- **Degraded hold signal**:
  - rising `typed_read_v2_degraded_refresh`
- **Failed hold signal**:
  - rising `typed_read_v2_failed` or `refresh_status=failed`
- **Parity hold signal**:
  - rising `typed_read_parity_shadow` mismatch with reason `identity|mixed`
- **Snapshot hold signal**:
  - any `typed_read_v2_snapshot_inconsistency`
- **Runtime gate decision**:
  - `typed_read_stage_gate_check.outcome=hold` => freeze stage
  - `typed_read_stage_gate_check.outcome=rollback` => rollback trigger
  - `typed_read_stage_gate_check.outcome=promote` => candidate for stage advance (after window completion)

## Alert Contract (Operator-Level)

### Rollback-Class Alerts (Immediate)
1. `typed_read_stage_gate_check.outcome=rollback`
   - Source of truth: `typed_read_stage_gate_check`
2. `typed_read_v2_snapshot_inconsistency`
   - Source of truth: snapshot inconsistency event stream
3. severe parity mismatch (`identity|mixed`) sustained in gate stats
   - Source of truth: `typed_read_stage_gate_check.severe_parity_mismatch_rate`

### Hold-Class Alerts (Freeze Expansion)
1. `typed_read_stage_gate_check.outcome=hold`
   - Source of truth: `typed_read_stage_gate_check`
2. failed/degraded warn-band breach without rollback threshold
   - Source of truth: `typed_read_stage_gate_check.failed_rate`, `degraded_rate`
3. parity mismatch warn-band breach
   - Source of truth: `typed_read_stage_gate_check.parity_mismatch_rate`
4. endpoint latency hold-band breach
   - Source of truth: gate p95 fields

### Watch Alerts (Investigate, No Automatic Action)
1. prolonged insufficient sample stagnation
   - condition: `gate_trigger=insufficient_window` for whole stage window
   - source of truth: `typed_read_stage_gate_check`
2. rising fallback trend while outcome still hold
   - source of truth: `fallback_rate` and `typed_read_v2_degraded_refresh`

## Panel-to-Decision Mapping
- Promote candidate:
  - gate outcome panel shows stable `promote` for full stage window
- Hold:
  - gate outcome panel includes `hold` during current window
- Rollback:
  - any `rollback` in gate outcome panel or hard snapshot alert

## Baseline Threshold Inputs (Fill After Stage 0)
- `BASELINE_DEGRADED_RATE = <fill>`
- `BASELINE_FAILED_RATE = <fill>`
- `BASELINE_PARITY_MISMATCH_RATE = <fill>`
- `WARN_MULTIPLIER = <fill>`
- `HOLD_MULTIPLIER = <fill>`

Until filled, use relative anomaly rule:
- clear sustained deviation from Stage 0 baseline => hold

## Baseline Fill Block (Operator)
Populate after Stage 0 capture:
- `BASELINE_DEGRADED_RATE = ____`
- `BASELINE_FAILED_RATE = ____`
- `BASELINE_PARITY_MISMATCH_RATE = ____`
- `BASELINE_PROFILE_LATENCY_MS_P50/P95 = ____ / ____`
- `BASELINE_RESULTS_LATENCY_MS_P50/P95 = ____ / ____`
- `BASELINE_OVERVIEW_LATENCY_MS_P50/P95 = ____ / ____`
