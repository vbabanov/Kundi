# Typed V2 Daily Verification

## Daily Checklist (Operator)
1. Confirm current rollout stage and cohort percentage.
2. Confirm active flags for canary cohort:
   - `USE_TYPED_V2_READ=true`
   - `ENABLE_V2_PARITY_SHADOW=true` (until stabilization decision)
   - `TYPED_V2_COHORT_PERCENT=<stage percent>`
   - optional explicit overrides:
     - `TYPED_V2_COHORT_ALLOWLIST=<student_id,...>`
     - `TYPED_V2_COHORT_DENYLIST=<student_id,...>`
     - `FORCE_LEGACY_V1_READ=true` (emergency rollback)
3. Verify key telemetry present:
   - `typed_read_cohort_decision`
   - `typed_read_refresh_start`
   - `typed_read_refresh_result`
   - `typed_read_v2_degraded_refresh` (if any)
   - `typed_read_v2_failed` (if any)
   - `typed_read_parity_shadow`
4. Verify refresh quality:
   - `read_mode=v2` only for in-cohort users
   - `refresh_status=success` stable
5. Verify v2 endpoint health through telemetry:
   - `/v2/profile` 200
   - `/v2/results` 200
   - `/v2/academic/overview` 200
6. Verify snapshot discipline:
   - same `snapshot_at` inside one refresh cycle
   - no `typed_read_v2_snapshot_inconsistency`
7. Verify no mixed snapshot regressions in UI spot checks.
8. Verify no raw IDs/internal keys surfaced in UI.
9. Verify no unexpected degraded/failed spikes vs baseline.
10. Read latest `typed_read_stage_gate_check`:
   - capture `outcome`
   - capture `gate_trigger`
   - capture `samples`, `failed_rate`, `degraded_rate`, `parity_mismatch_rate`
11. Record daily decision:
   - continue stage
   - hold stage
   - rollback stage
12. Append decision record to stage journal.
13. Capture cohort evidence from `typed_read_cohort_decision`:
   - `cohort_reason`
   - `cohort_percent`
   - `cohort_bucket`

## Operator Decision Loop (Manual)
1. Gather evidence for trailing window:
   - refresh outcomes
   - fallback/degraded
   - parity
   - snapshot consistency
   - gate decision event
2. Classify:
   - if gate outcome is `rollback` -> execute rollback runbook
   - if gate outcome is `hold` -> freeze stage and investigate
   - if gate outcome is `promote` -> keep current stage until window complete, then promote
3. Record:
   - decision + trigger + operator sign-off
   - links to log extract/screenshot evidence

## Daily Evidence Snippets
```powershell
Select-String -Path D:\Kundi\reports\*.log -Pattern 'typed_read_cohort_decision|typed_read_refresh_result|typed_read_v2_failed|typed_read_v2_degraded_refresh|typed_read_parity_shadow|typed_read_v2_snapshot_inconsistency|typed_read_stage_gate_check' | ForEach-Object { $_.Line }
```

## Daily Monitoring Snapshot (Mandatory)
```powershell
powershell -ExecutionPolicy Bypass -File D:\Kundi\infra\scripts\typed-v2-monitoring-snapshot.ps1 `
  -Workspace D:\Kundi `
  -InputLog D:\Kundi\reports\stage0_flutter.log
```

Required outputs:
- `D:\Kundi\reports\typed_v2_monitoring_snapshot.json`
- `D:\Kundi\reports\typed_v2_monitoring_snapshot.md`

## Daily Notification Delivery (Mandatory)
```powershell
powershell -ExecutionPolicy Bypass -File D:\Kundi\infra\scripts\typed-v2-telegram-notify.ps1 `
  -Workspace D:\Kundi `
  -SnapshotJson D:\Kundi\reports\typed_v2_monitoring_snapshot.json
```

If delivery fails:
- keep stage unchanged
- continue manual operator decision from snapshot artifact
- record delivery failure in daily decision record

Linux server path (preferred for server-side loop):

```bash
systemctl start kundi-typed-v2-monitor.service
journalctl -u kundi-typed-v2-monitor.service -n 80 --no-pager
```

Disable timer temporarily:

```bash
systemctl disable --now kundi-typed-v2-monitor.timer
```

## Required Daily Fields
- `read_mode`
- `refresh_status`
- `last_refresh_mode`
- `fallback_reason`
- `trace_id`
- `window_key`
- `snapshot_at`
- `rows_written`
- `rows_deleted`
- `results_count`
- `aggregates_count`
- `attendance_count`
- `typed_read_parity_shadow_mismatch_reason`

## UI Raw-ID Probe (Daily Spot Check)
```powershell
$adb='C:\Users\baban\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$dump='D:\Kundi\reports\daily_ui_dump.xml'
& $adb shell uiautomator dump /sdcard/window_dump.xml | Out-Null
& $adb pull /sdcard/window_dump.xml $dump | Out-Null
Select-String -Path $dump -Pattern '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' -CaseSensitive:$false
```
Expected:
- no user-visible UUID/internal keys in profile/grades/lessons/homework flows.

## Daily Decision Rules
- If any hold trigger active -> do not expand rollout.
- If sustained hold trigger -> rollback to previous stage.
- If no trigger and metrics stable for full window -> continue per ladder.
- Runtime gate event precedence:
  - `rollback` > `hold` > `promote`
