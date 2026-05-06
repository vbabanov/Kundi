# Mobile Typed Read Rollout (Phase 3)

## PR1 baseline (fixed release invariants)
- v2 refresh writes are atomic:
  - all v2 cache tables are written inside one transaction-bound entrypoint (`applyV2RefreshSnapshot`).
  - stale cleanup is executed in the same transaction.
  - no partial commit is allowed.
- single refresh cycle uses one `snapshot_at` for:
  - `/v2/profile`
  - `/v2/results`
  - `/v2/academic/overview`
- active v2 snapshot pointer is published only on `success`.
- `degraded` and `failed` refresh outcomes never publish a new active v2 snapshot.
- refresh status is always persisted (`success|degraded|failed`).
- v2 refresh path must not write into legacy `canonical_grades_cache`.

## Source selection policy (`USE_TYPED_V2_READ`)
- `false` (default):
  - refresh source = `v1` endpoints.
- `true`:
  - refresh source = `v2` endpoints first.
  - fallback to `v1` is allowed only for transport-level failures.

## Transport fallback rules
Fallback from `v2` -> `v1` is allowed only for:
- network timeout / connection errors
- `429`, `502`, `503`, `504`

Fallback is **not** allowed for:
- schema mismatch / parsing mismatch (`FormatException`)
- auth/session responses (`401`, `403`)
- domain contract failures (`400`, `404`, `409`, `422`)

## No v1/v2 mixed UI snapshot rule
- Mode is selected once per refresh run.
- In v2 mode:
  - fetch `/v2/profile`, `/v2/results`, `/v2/academic/overview`
  - decode typed DTOs
  - then write cache.
- If v2 transport fallback is triggered:
  - switch full refresh run to v1 path.
- Metadata stored:
  - `active_read_mode`
  - `active_window_key`
  - `active_snapshot_at`
  - `last_refresh_status`
  - `last_refresh_mode`

## Refresh result semantics (authoritative)
- `success`:
  - typed v2 read succeeded end-to-end.
  - active v2 snapshot pointer advances.
- `degraded`:
  - transport fallback from v2 to v1 occurred.
  - event `typed_read_v2_degraded_refresh` is emitted.
  - `last_refresh_mode = degraded_v1_fallback`.
  - active v2 snapshot pointer does not advance.
- `failed`:
  - no fallback was allowed or refresh was inconsistent.
  - active v2 snapshot pointer does not advance.

## Window / stale cleanup in cache
- v2 rows carry:
  - `window_key`
  - `snapshot_at`
- stale rows:
  - same `window_key`, older `snapshot_at`
- cleanup runs on each v2 refresh for:
  - `canonical_provider_identity_cache_v2`
  - `canonical_local_app_profile_cache_v2`
  - `canonical_results_cache_v2`
  - `canonical_aggregates_cache_v2`
  - `canonical_lessons_cache_v2`
  - `canonical_attendance_cache_v2`
  - `canonical_overview_counts_cache_v2`
  - `canonical_overview_highlights_cache_v2`

## Refresh/update guarantees covered by tests
- `read_source_policy_test.dart`:
  - fallback allowed only for transport failures
  - no fallback for schema/auth classes
- `v2_read_models_test.dart`:
  - provider/local split DTO parsing
  - schema mismatch detection via typed parse failure
- `pr1_integrity_release_gate_test.dart`:
  - atomic rollback safety (no partial commit)
  - active snapshot publish only on `success`
  - `success|degraded|failed` refresh status persistence
  - coalesced refresh join in-flight behavior
  - no legacy `canonical_grades_cache` writes from v2 path

## Canary parity telemetry
When `ENABLE_V2_PARITY_SHADOW=true` and read mode is v2:
- app performs best-effort shadow reads on:
  - `/v1/profile`
  - `/v1/grades`
  - `/v1/lessons`
- emits `typed_read_parity_shadow` log with:
  - `count_match`
  - `identity_match`
  - `mood_match`
  - `aggregate_match`
  - `typed_read_parity_shadow_mismatch_reason`:
    - `count`
    - `identity`
    - `mood`
    - `aggregate`
    - `mixed`
  - mismatch counters:
    - `mood_mismatch`
    - `identity_mismatch`
    - `aggregate_mismatch`
  - status `ok|mismatch|failed`

## Required refresh telemetry events
- `typed_read_refresh_start`
- `typed_read_refresh_result`
- `typed_read_refresh_coalesced`
- `typed_read_v2_transport_fallback`
- `typed_read_v2_degraded_refresh`
- `typed_read_v2_failed`

## Legacy v1 cleanup policy (safe)
Do not remove v1 map-based path until:
- confidence window gate from `docs/runbooks/v2-read-canary-smoke.md` is passed.
- dedicated cleanup PR keeps rollback switch for one more release.
