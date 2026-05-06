# PR5 Rollout Checklist

## Scope
- Stabilization and rollout safety only.
- No layout redesign.
- No home/avatar/chat/gamification/media changes.
- No domain model expansion.

## Pre-Release Engineering Checks
- `main_shell_page.dart` changed only for wiring/flag behavior.
- `summary_repository_impl.dart` changed only for cleanup/binding guarantees/regression safety.
- No mixed snapshot render path in PR2/PR3/PR4 surfaces.
- No v2 write/read path into legacy `canonical_grades_cache` for v2 refresh flow.

## Mandatory Test Matrix
- Unit:
  - `read_source_policy_test.dart`
  - `parity_shadow_reason_test.dart`
  - `auth_refresh_orchestration_wp3_test.dart`
  - `repository_v2_plumbing_wp4_test.dart`
- Feature unit/widget:
  - profile v2 split tests
  - grades v2 mode tests
  - lessons/summary v2 binding tests
- Regression:
  - no raw IDs resurfacing
  - no mixed snapshot render
  - fallback only for transport failures

## Staging Smoke Requirements
- `read_mode=v2`
- `refresh_status=success`
- `/v2/profile=200`, `/v2/results=200`, `/v2/academic/overview=200`
- typed refresh telemetry includes:
  - `trace_id`
  - `window_key`
  - `snapshot_at`
  - `rows_written`
  - `rows_deleted`
  - `results_count`
  - `aggregates_count`
  - `attendance_count`

## Hold Triggers (Stop/Do-Not-Expand Canary)
- **degraded spike**: sudden increase of `typed_read_v2_degraded_refresh`.
- **failed spike**: increase of `typed_read_v2_failed` or `refresh_status=failed`.
- **parity mismatch spike**: increase of `typed_read_parity_shadow` mismatch outcomes.
- **mixed snapshot regression**: any `typed_read_v2_snapshot_inconsistency` or mixed-snapshot UI evidence.
- **raw IDs resurfacing**: any user-facing UUID/internal key rendering in profile/grades/lessons/homework surfaces.

## Canary Ladder
- 1-2% -> 5% -> 10-20% -> 50% -> 100%
- Move to next step only after hold triggers stay clear for the observation window.

