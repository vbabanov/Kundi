# Typed V2 Rollback Runbook

## When to Roll Back
Rollback to previous stage when:
- degraded spike is sustained
- failed spike is sustained
- parity mismatch spike is sustained (identity/mixed priority)
- mixed snapshot regression appears
- raw IDs resurface in user-visible surfaces
- visible correctness regression confirmed

Hard rollback when:
- data integrity risk
- silent corruption suspicion

## Rollback Steps (Operational)
1. Freeze rollout expansion immediately.
2. Switch canary cohort to previous stable config.
3. If needed, disable typed v2 read for affected cohort:
   - set `FORCE_LEGACY_V1_READ=true`
   - set `TYPED_V2_COHORT_PERCENT=0`
4. Keep telemetry capture on and annotate rollback timestamp.
5. Run smoke validation on rolled-back cohort:
   - login -> refresh -> profile/grades/lessons
6. Confirm stabilization metrics after rollback.

## Rollback Trigger Priority
Execute rollback immediately when any of the following appears:
1. `typed_read_stage_gate_check.outcome=rollback`
2. `typed_read_v2_snapshot_inconsistency` event present
3. confirmed correctness regression with user-visible impact

Hold-only condition (no immediate rollback):
- `typed_read_stage_gate_check.outcome=hold` and no rollback-class event

## Rollback Execution Snippets
Use the same release mechanism used for canary flag distribution.

1. Freeze:
- stop percentage increase in rollout control plane.

2. Revert cohort flag:
- `FORCE_LEGACY_V1_READ=true` for impacted cohort.
- clear `TYPED_V2_COHORT_ALLOWLIST`.
- keep `TYPED_V2_COHORT_DENYLIST` for known-bad IDs if needed.
- keep `ENABLE_V2_PARITY_SHADOW=true` while validating rollback stability.

3. Capture post-rollback proof:
```powershell
Select-String -Path D:\Kundi\reports\*.log -Pattern 'typed_read_refresh_result|typed_read_v2_failed|typed_read_v2_degraded_refresh|typed_read_parity_shadow' | ForEach-Object { $_.Line }
```

## Post-Rollback Validation
- `refresh_status=success` recovered to stable baseline.
- no new `typed_read_v2_failed` spike.
- no mixed snapshot incidents.
- no raw IDs in UI.
- runtime gate returns to `hold` or `promote` (no `rollback`) for validation window.

## Post-Rollback Verification Snippet
```powershell
Select-String -Path D:\Kundi\reports\*.log -Pattern 'typed_read_stage_gate_check|typed_read_refresh_result|typed_read_v2_snapshot_inconsistency' | ForEach-Object { $_.Line }
```

## Incident Evidence Bundle
- logs covering:
  - before rollback
  - rollback moment
  - after rollback
- screenshots of impacted surfaces
- stage and cohort metadata
- trigger classification:
  - degraded
  - failed
  - parity mismatch
  - mixed snapshot
  - raw IDs

## Recovery Exit Criteria
Do not re-attempt expansion until:
- root cause identified
- fix validated in staging smoke
- Stage 0 checklist re-passed
- release owner approves re-entry
