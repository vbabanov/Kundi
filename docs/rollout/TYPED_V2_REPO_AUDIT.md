# Typed V2 Repo Audit vs Accepted Rollout Runbook

Date: 2026-04-06

## Checked Areas
1. Feature flags and toggles
2. Telemetry events + gate fields
3. Snapshot and fallback guardrails
4. Smoke path availability (login -> refresh -> profile/grades/lessons)
5. Runbook/operator docs completeness

## Findings

### Confirmed wired in code
- `USE_TYPED_V2_READ` present in `mobile/lib/shared/providers/providers.dart`
- `ENABLE_V2_PARITY_SHADOW` present in `mobile/lib/shared/providers/providers.dart`
- Required telemetry events present in `mobile/lib/features/auth/data/auth_repository_impl.dart`:
  - `typed_read_refresh_start`
  - `typed_read_refresh_result`
  - `typed_read_refresh_coalesced`
  - `typed_read_v2_degraded_refresh`
  - `typed_read_v2_failed`
  - `typed_read_parity_shadow`
  - `typed_read_v2_snapshot_inconsistency`
- v2 triplet calls wired in same refresh cycle:
  - `/v2/profile`
  - `/v2/results`
  - `/v2/academic/overview`
- Snapshot discipline guardrails present:
  - one request-level `snapshot_at` propagated through triplet
  - inconsistency emits event and fails cycle
- Active snapshot publish discipline present in cache store:
  - publish active state on success only
  - degraded/failed do not advance active snapshot
- Fallback discipline present via `ReadSourcePolicy` (transport-only fallback).

### Gaps found during audit

#### Blocker for Stage 0
- None in code wiring for typed-v2 rollout execution.

#### Should-fix before Stage 1
1. Operator docs needed stronger deterministic smoke action wording:
   - capture before login/refresh
   - do not stop until completion marker
2. Stage gate docs needed explicit baseline-fill table and threshold placeholders.
3. Daily checklist needed explicit raw-ID probe command and required `last_refresh_mode`.

#### Can wait until later stabilization
1. Full automation for older-week visual proof can remain manual.
2. Latency SLO hard thresholds can be added after baseline capture.

## Actions Applied
- Updated:
  - `docs/rollout/TYPED_V2_STAGE0_CHECKLIST.md`
  - `docs/rollout/TYPED_V2_STAGE_GATES.md`
  - `docs/rollout/TYPED_V2_DAILY_VERIFICATION.md`
  - `docs/rollout/TYPED_V2_ROLLBACK_RUNBOOK.md`
  - `docs/rollout/TYPED_V2_TELEMETRY_MATRIX.md`

These updates close pre-Stage-1 runbook execution gaps without changing product architecture.
