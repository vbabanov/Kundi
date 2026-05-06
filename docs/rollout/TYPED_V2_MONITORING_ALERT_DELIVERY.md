# Typed V2 Monitoring and Alert Delivery

## Goal
Provide a practical operator-facing monitoring loop for typed v2 rollout using existing runtime signals.

## Scope
- Manual-first operations
- No automatic promote/rollback actions
- No contract or business-logic changes

## Source-Of-Truth Order (First / Second / Third)
1. First look:
   - `typed_read_stage_gate_check` (latest outcome and trigger)
2. Second look:
   - `typed_read_refresh_result` (success/degraded/failed mix, latency fields, fallback reason)
3. Third look:
   - `typed_read_parity_shadow` and `typed_read_v2_snapshot_inconsistency`

If signals conflict, precedence is fixed:
- `rollback` > `hold` > `promote`

For server-side snapshots produced by the backend-only adapter:
- The adapter is a backend health veto/check, not the rollout promotion source.
- `missing_mobile_gate_signal_backend_adapter` means mobile-only gate/parity signals are outside server journald coverage.
- If backend samples are sufficient and backend failure/fallback rates are clean, this trigger is watch-class only and must not override a captured mobile `typed_read_stage_gate_check outcome=promote`.
- If the backend adapter emits rollback or hold for backend-observable failures, treat it as a veto and freeze/rollback according to the runbook.

## Monitoring Snapshot Artifact
Generate snapshot from captured log:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Kundi\infra\scripts\typed-v2-monitoring-snapshot.ps1 `
  -Workspace D:\Kundi `
  -InputLog D:\Kundi\reports\stage0_flutter.log
```

Outputs:
- `D:\Kundi\reports\typed_v2_monitoring_snapshot.json`
- `D:\Kundi\reports\typed_v2_monitoring_snapshot.md`

These outputs are the operator handoff artifact for stage review.

Server-side truthful adapter (backend signals only):

```bash
python3 /root/kundi-prod/shared/ops/typed-v2/typed-v2-backend-monitoring-snapshot.py \
  --workspace /root/kundi-prod/shared/ops/typed-v2 \
  --unit kundi-prod-api.service \
  --since "1 hour ago"
```

Server-side outputs:
- `/root/kundi-prod/shared/ops/typed-v2/reports/typed_v2_backend_monitoring_snapshot.json`
- `/root/kundi-prod/shared/ops/typed-v2/reports/typed_v2_backend_monitoring_snapshot.md`

Notes:
- backend adapter uses only server-available signals (`v2_read_*`, `backend.read.*`, `backend.ingest.*` when present)
- mobile-only signals remain explicitly marked as unavailable in snapshot coverage fields
- backend-only `mobile_only_gate_missing` is non-blocking once backend sample/health checks are satisfied; the stage decision still requires the mobile gate artifact.

## Linux-Native Telegram Sender (Server)
Send alert from backend snapshot JSON without PowerShell:

```bash
python3 /root/kundi-prod/shared/ops/typed-v2/typed-v2-telegram-notify.py \
  --snapshot-json /root/kundi-prod/shared/ops/typed-v2/reports/typed_v2_backend_monitoring_snapshot.json
```

Dry-run:

```bash
python3 /root/kundi-prod/shared/ops/typed-v2/typed-v2-telegram-notify.py \
  --snapshot-json /root/kundi-prod/shared/ops/typed-v2/reports/typed_v2_backend_monitoring_snapshot.json \
  --dry-run
```

Secrets are read from environment:
- `KUNDI_TYPED_V2_TELEGRAM_BOT_TOKEN`
- `KUNDI_TYPED_V2_TELEGRAM_CHAT_ID`

Recommended server env file:
- `/root/kundi-prod/shared/env/typed-v2-monitoring.env`

## Alert Classes

### Rollback-Class (Immediate Action)
- Trigger:
  - `typed_read_stage_gate_check.outcome=rollback`
  - or snapshot inconsistency event present
- Action:
  - execute rollback runbook immediately

### Hold-Class (Freeze Expansion)
- Trigger:
  - `typed_read_stage_gate_check.outcome=hold`
- Action:
  - freeze rollout stage
  - continue investigation and evidence capture

### Watch-Class (Operator Attention)
- Trigger:
  - `gate_trigger=insufficient_window`
  - missing gate event (`no_gate_signal`)
  - fallback trend while not in rollback
- Action:
  - keep stage unchanged
  - improve sample quality / continue monitoring

## Alert Delivery Contract (Current Phase)
- Delivery medium:
  - Telegram notification for alert class delivery
  - daily operator review + snapshot artifact + stage decision journal
- Required fields in decision record:
  - gate outcome
  - gate trigger
  - samples
  - failed/degraded/fallback rates
  - parity mismatch and severe parity mismatch rates
  - snapshot inconsistency count
  - p95 latencies (profile/results/overview)

## Lightweight Notification Channel (Telegram)
This phase uses Telegram as the minimal solo-operator delivery channel.
No auto-promote/auto-rollback behavior is introduced.

Required configuration:
- `KUNDI_TYPED_V2_TELEGRAM_BOT_TOKEN`
- `KUNDI_TYPED_V2_TELEGRAM_CHAT_ID`

Send notification from generated snapshot:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Kundi\infra\scripts\typed-v2-telegram-notify.ps1 `
  -Workspace D:\Kundi `
  -SnapshotJson D:\Kundi\reports\typed_v2_monitoring_snapshot.json
```

Dry-run test (no send):

```powershell
powershell -ExecutionPolicy Bypass -File D:\Kundi\infra\scripts\typed-v2-telegram-notify.ps1 `
  -Workspace D:\Kundi `
  -SnapshotJson D:\Kundi\reports\typed_v2_monitoring_snapshot.json `
  -DryRun
```

Notification payload includes:
- alert class (`rollback|hold|watch|promote`)
- latest gate outcome and trigger
- key rates (`failed/degraded/fallback/parity_mismatch`)
- snapshot inconsistency count
- sample count
- snapshot file path

If Telegram send fails:
- rollout behavior is unchanged
- operator continues manual loop
- attach snapshot artifact manually to stage journal

## Stage Decision Rule (Manual)
- If rollback-class alert active: rollback
- Else if hold-class alert active: hold
- Else if latest gate is promote and window is complete: promote
- Else: stay in current stage and continue watch
