# V2 Read Canary and Staging Smoke Runbook

## Goal
Validate end-to-end flow on staging:
`login -> refresh -> ingest -> typed reads -> cache fill`
with rollback-safe behavior.

## Scope guard
- This runbook validates PR1 refresh integrity baseline only.
- No UI surface rollout checks (PR2+ scope) are included here.

## Canary flags
- `USE_TYPED_V2_READ=true`
- optional parity shadow:
  - `ENABLE_V2_PARITY_SHADOW=true`

## Smoke sequence
1. Login in mobile with staging account.
2. Ensure ingest is executed (`ingest_start` / `ingest_result` logs).
3. Ensure typed read refresh starts:
   - `typed_read_refresh_start` with `read_mode=v2`.
4. Validate unified snapshot request context:
   - same `snapshot_at` query param is sent to:
     - `/v2/profile`
     - `/v2/results`
     - `/v2/academic/overview`
5. Ensure cache write completed atomically:
   - `typed_read_refresh_result` with:
     - `read_mode=v2`
     - `refresh_status=success`
     - `rows_written > 0`
6. Verify active v2 snapshot publication semantics:
   - on `success`: active pointer advances.
   - on `degraded|failed`: active pointer does not advance.
7. Verify no legacy contamination:
   - v2 refresh must not write to `canonical_grades_cache`.
8. If parity shadow enabled:
   - check `typed_read_parity_shadow` status (`ok|mismatch`).

## Required telemetry fields
Track these fields in mobile/backend logs:
- `trace_id` (mobile -> backend `X-Trace-Id`)
- `read_mode`
- `provider`
- `window_key`
- `snapshot_at`
- `fallback_reason` (when fallback happens)
- `latency_profile_ms`
- `latency_results_ms`
- `latency_overview_ms`
- `results_count`
- `aggregates_count`
- `lessons_count`
- `attendance_count`
- `rows_deleted`
- `rows_written`
- `refresh_status`
- `last_refresh_mode`
- `typed_read_parity_shadow_mismatch_reason`

Backend event names that must be present for endpoint-level diagnosis:
- `v2_read_profile`
- `v2_read_results`
- `v2_read_overview`

## Fallback policy (strict)
Allowed `v2 -> v1` fallback:
- transport failures only (`timeout/network`, `429/502/503/504`)

No fallback:
- schema mismatch
- auth/session failures (`401/403`)
- domain/contract failures (`400/404/409/422`)

After allowed transport fallback:
- emit `typed_read_v2_degraded_refresh`
- persist `last_refresh_mode = degraded_v1_fallback` in cache metadata
- keep active v2 snapshot pointer unchanged

## Required refresh events checklist
Every smoke run must show the expected event sequence:
- success path:
  - `typed_read_refresh_start`
  - `typed_read_refresh_result` (`refresh_status=success`)
- degraded path:
  - `typed_read_refresh_start`
  - `typed_read_v2_transport_fallback`
  - `typed_read_v2_degraded_refresh`
  - `typed_read_refresh_result` (`refresh_status=degraded`, `last_refresh_mode=degraded_v1_fallback`)
- failed path:
  - `typed_read_refresh_start`
  - `typed_read_v2_failed`
  - `typed_read_refresh_result` (`refresh_status=failed`)

## Monitoring Hookup (Operator Visibility)
After smoke capture, build an operator snapshot:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Kundi\infra\scripts\typed-v2-monitoring-snapshot.ps1 `
  -Workspace D:\Kundi `
  -InputLog D:\Kundi\reports\stage0_flutter.log
```

Use generated `typed_v2_monitoring_snapshot.md` as stage review input.

## Canary confidence window and cleanup gate
Minimum confidence window before removing v1 map-based read path:
- 7 consecutive days on staging canary
- no unresolved `typed_read_v2_failed` with `fallback_reason` not equal `transport_failure`
- parity mismatch rate <= 2% (shadow telemetry)
- no auth/session issues masked as fallback

Only after gate passes:
1. disable v1 fallback in canary cohort,
2. keep rollback switch for 1 additional release,
3. then remove legacy v1 read path code in a dedicated cleanup change.

## PR1 release-gate baseline tests
Run before canary expansion:
- `flutter test test/unit/pr1_integrity_release_gate_test.dart`
- expected:
  - all tests green
  - no flaky retry needed
