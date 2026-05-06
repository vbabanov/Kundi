# Typed V2 Stage Gates

## Current Strategy State (2026-04-16)
- Stage 1 is active and observed.
- Stage 2 is not started.
- Stage 2 is intentionally deferred by product/tester availability strategy, not by typed v2 quality failure.

State classification:
- Technical blocker: none critical for typed v2 quality at current Stage 1 window.
- Operational blocker: no proven delivery reach beyond the current single anchor ADB canary.
- Business/product defer: intentional hold until new real tester inflow appears with upcoming product readiness (design, avatar, WhatsApp, camera).

## Approved Rollout Sequence
1. Stage 0: pre-canary staging sanity
2. Stage 1: 1-2% (24h)
3. Stage 2: 5% (24h)
4. Stage 3: 10-20% (48h)
5. Stage 4: 50% (48h)
6. Stage 5: 100%

## Gate Logic (Non-negotiable)
- Do not move to next stage if any hold trigger is active.
- If hold trigger is sustained, freeze expansion.
- If user-visible correctness regression appears, rollback to previous stage.
- Hard rollback for data integrity / silent corruption suspicion.
- Runtime gate decision is emitted as:
  - `typed_read_stage_gate_check` with outcome `promote|hold|rollback`.
- Stage semantics in this phase:
  - `active`: typed v2 read path
  - `transitional`: degraded fallback to v1
  - `legacy`: stable v1-only path

## Runtime Source Of Truth
- Primary event for operator decision:
  - `typed_read_stage_gate_check`
- Decision mapping:
  - `outcome=promote` -> stage can be promoted only after full stage window elapsed
  - `outcome=hold` -> freeze current stage (no cohort increase)
  - `outcome=rollback` -> execute rollback runbook immediately
- Supporting evidence events:
  - `typed_read_refresh_result`
  - `typed_read_v2_degraded_refresh`
  - `typed_read_v2_failed`
  - `typed_read_parity_shadow`
  - `typed_read_v2_snapshot_inconsistency`

## Hold Triggers
1. Degraded spike:
   - surge of `typed_read_v2_degraded_refresh`
2. Failed spike:
   - surge of `typed_read_v2_failed` or `refresh_status=failed`
3. Parity mismatch spike:
   - surge of `typed_read_parity_shadow` mismatches, especially:
     - `typed_read_parity_shadow_mismatch_reason=identity`
     - `typed_read_parity_shadow_mismatch_reason=mixed`
4. Mixed snapshot regression:
   - any `typed_read_v2_snapshot_inconsistency`
   - or UI evidence of mixed snapshot render
5. Raw IDs resurfacing:
   - any UUID/internal key shown in user-facing profile/grades/lessons/homework

## Threshold Policy
Window:
- trailing 24h from runtime gate event stream
- minimum `20` refresh samples before `promote` is allowed

Promote band:
- failed rate `<= 1%`
- degraded rate `<= 3%`
- parity mismatch rate `<= 5%`
- profile p95 latency `<= 1200 ms`
- results p95 latency `<= 1800 ms`
- overview p95 latency `<= 1400 ms`
- snapshot inconsistency count `== 0`

Hold band:
- failed rate `> 1%` and `< 8%` (hard hold over `3%`)
- degraded rate `> 3%` and `< 20%` (hard hold over `7%`)
- parity mismatch rate `> 5%` and `< 10%`
- profile/results/overview p95 above promote SLO but below rollback trigger
- insufficient sample window (`< 20`)

Rollback triggers:
- any snapshot inconsistency (`typed_read_v2_snapshot_inconsistency > 0`)
- failed rate `>= 8%`
- degraded rate `>= 20%`
- severe parity mismatch rate (`identity|mixed`) `>= 3%`

## Stage Operating Contract

| Stage | Cohort | Minimum Window | Minimum Samples | Promote Rule | Hold Rule | Rollback Trigger |
|---|---|---|---|---|---|---|
| Stage 0 | staging sanity | single smoke window | 1 deterministic cycle | all smoke checks pass | any smoke check missing | snapshot inconsistency / hard correctness issue |
| Stage 1 | 1-2% | 24h | 20 | latest gate decision = `promote` and no unresolved Sev1/Sev2 | latest gate decision = `hold` | latest gate decision = `rollback` |
| Stage 2 | 5% | 24h | 20 | same as Stage 1 | same as Stage 1 | same as Stage 1 |
| Stage 3 | 10-20% | 48h | 40 | gate remains in `promote` band for window | any `hold` in window blocks advance | any `rollback` in window |
| Stage 4 | 50% | 48h | 40 | gate remains in `promote` band for window | any `hold` in window blocks advance | any `rollback` in window |
| Stage 5 | 100% | 72h post-promotion watch | 60 | stable window completed | prolonged `hold` => freeze at 100% and investigate | any `rollback` => revert to previous stable stage |

## Stage Gate Record (Fill During Operation)
Populate this table during execution and attach in daily ops note.

| Stage | Window | Baseline / Threshold Source | Decision | Sign-off |
|---|---|---|---|---|
| Stage 0 | pre-canary | staging smoke baseline | pass / hold | release owner |
| Stage 1 | 1-2% / 24h | Stage 0 baseline | pass / hold / rollback | release owner |
| Stage 2 | 5% / 24h | Stage 1 observed | pass / hold / rollback | release owner |
| Stage 3 | 10-20% / 48h | Stage 2 observed | pass / hold / rollback | release owner |
| Stage 4 | 50% / 48h | Stage 3 observed | pass / hold / rollback | release owner |
| Stage 5 | 100% | Stage 4 observed | pass / hold / rollback | release owner |

## Evidence Required to Open Stage 1
- Stage 0 pass checklist complete
- Stage 0 evidence package archived
- baseline values for degraded/failed/parity mismatch recorded
- release owner sign-off

## Stage Promotion Checklist
- Current stage window completed (24h/48h as defined)
- No active hold trigger
- No unresolved Sev1/Sev2 correctness issue
- Snapshot discipline remains clean
- Rollback readiness confirmed
- Latest runtime gate decision is `promote` for trailing 24h window

## Return-To-Stage-2 Entry Criteria
Stage 2 may be re-opened only when all are true:
1. Stage 1 still green on latest observed window.
2. Operator loop is healthy (monitoring snapshot + Telegram delivery working).
3. Delivery reach beyond single anchor ADB device is available:
   - new real testers, or
   - real distribution reach to non-anchor devices.
4. Stage 2 delivery evidence can include non-anchor install/runtime proof.
5. Rollout docs are current with actual execution path.

## Required Stage Decision Record
For every stage review, operator must record:
- stage id and cohort percentage
- review window timestamps
- sample count observed
- latest `typed_read_stage_gate_check` payload
- decision (`promote|hold|rollback`)
- operator and timestamp
- link to evidence bundle (logs/screenshots)
