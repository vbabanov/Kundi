# Typed V2 Operator Rollout Loop

## Purpose
This document connects runtime gate decisions to the manual rollout process.
It is intentionally manual-first and does not introduce automatic mode switching.

## Current Mode (2026-04-16)
- Active mode: **Stage 1 hold-and-observe**.
- Stage 2 is intentionally deferred and is not an active execution target right now.
- Reason for defer: product/tester availability strategy, not typed v2 runtime failure.

## Scope Guard
- No API contract changes
- No ingest/read semantic changes
- No automatic rollback logic in client/backend runtime
- Operator remains final decision owner

## Inputs (Source Of Truth)
1. `typed_read_stage_gate_check`
2. `typed_read_refresh_result`
3. `typed_read_v2_degraded_refresh`
4. `typed_read_v2_failed`
5. `typed_read_parity_shadow`
6. `typed_read_v2_snapshot_inconsistency`
7. `typed_read_cohort_decision`

## Stage Decision Source-Of-Truth
- Promotion/hold/rollback decisions for a mobile rollout stage are made from the captured mobile gate artifact:
  - `typed_read_stage_gate_check`
  - plus its supporting refresh/parity/snapshot events.
- The server-side backend adapter is a backend health check and veto signal only.
- `missing_mobile_gate_signal_backend_adapter` is expected for backend-only snapshots because mobile gate/parity events are not present in server journald.
- When backend samples are sufficient and backend health is clean, `missing_mobile_gate_signal_backend_adapter` is watch-class, not a blocking hold.
- If the backend adapter reports backend-observable rollback/hold conditions (for example backend read failure rate or insufficient backend samples), freeze expansion until resolved.

## Delivery Reach Gate (Stage 2+)
- Do not treat Stage 2 as started when a new config/build exists only on the anchor ADB canary device.
- Stage 2 requires evidence that delivery reached non-anchor tester devices.
- Recommended path is documented in `docs/rollout/TYPED_V2_STAGE2_DELIVERY_PATH.md`.
- For Stage 2 review, operator must attach:
  - at least one non-anchor install confirmation
  - non-anchor runtime evidence (`typed_read_cohort_decision`, `typed_read_refresh_result`, `typed_read_stage_gate_check`)

## Return-To-Stage-2 Preconditions
Before reopening Stage 2 execution:
1. Stage 1 latest gate window remains green.
2. Monitoring/Telegram loop is healthy.
3. Real non-anchor tester reach is available.
4. Stage 2 delivery evidence plan is ready (install + runtime + operator snapshot).

## Near-Term Product Priority Alignment
Rollout expansion is intentionally waiting for product-completion readiness that should naturally increase real tester inflow:
1. design completion
2. avatar completion
3. WhatsApp flow completion
4. camera flow completion

Primary operational snapshot command:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Kundi\infra\scripts\typed-v2-monitoring-snapshot.ps1 `
  -Workspace D:\Kundi `
  -InputLog D:\Kundi\reports\stage0_flutter.log
```

Snapshot contract:
- `D:\Kundi\reports\typed_v2_monitoring_snapshot.json`
- `D:\Kundi\reports\typed_v2_monitoring_snapshot.md`

Server-side adapter command (Linux, backend-truthful):

```bash
python3 /root/kundi-prod/shared/ops/typed-v2/typed-v2-backend-monitoring-snapshot.py \
  --workspace /root/kundi-prod/shared/ops/typed-v2 \
  --unit kundi-prod-api.service \
  --since "1 hour ago"
```

Server-side full monitoring loop (snapshot + telegram):

```bash
bash /root/kundi-prod/shared/ops/typed-v2/typed-v2-monitoring-loop.sh
```

systemd controls:

```bash
systemctl start kundi-typed-v2-monitor.service
systemctl status kundi-typed-v2-monitor.service --no-pager
systemctl enable --now kundi-typed-v2-monitor.timer
systemctl list-timers --all | grep kundi-typed-v2-monitor
```

## Manual Rollout Loop
1. Pre-stage check
   - verify target cohort/flags
   - verify `TYPED_V2_COHORT_PERCENT` matches stage target
   - verify telemetry ingestion is healthy
   - verify rollback path ready
2. During-stage watch
   - generate monitoring snapshot artifact
   - send Telegram notification from snapshot
   - monitor gate outcome stream
   - verify refresh success/degraded/failed mix
   - verify snapshot consistency and parity reasons
   - compare backend adapter health with the mobile gate artifact; backend-only missing mobile signals do not override a clean mobile gate
3. Stage decision
   - `rollback`: execute rollback runbook immediately
   - `hold`: freeze stage, investigate, no cohort increase
   - `promote`: only promote after full stage window + minimum samples
4. Record and sign-off
   - append stage decision record
   - include operator, timestamp, evidence links

## Stage Decision Card Template
- Stage:
- Cohort:
- Window start/end:
- Samples:
- Latest gate outcome:
- Gate trigger:
- Failed rate:
- Degraded rate:
- Fallback rate:
- Parity mismatch rate:
- Severe parity mismatch rate:
- Snapshot inconsistency count:
- Decision (promote/hold/rollback):
- Operator:
- Evidence links:

## Escalation Rules
- Any rollback-class trigger => escalate immediately (no waiting for window end)
- Hold-class triggers => escalate if sustained for full watch window
- Insufficient samples => keep stage unchanged and continue watch

## Output Artifact
Store one decision card per stage review in release notes / ops journal.
Attach monitoring snapshot JSON/MD in the same record.

## Notification Step (Telegram)
1. Build snapshot:
```powershell
powershell -ExecutionPolicy Bypass -File D:\Kundi\infra\scripts\typed-v2-monitoring-snapshot.ps1 `
  -Workspace D:\Kundi `
  -InputLog D:\Kundi\reports\stage0_flutter.log
```
2. Send alert notification:
```powershell
powershell -ExecutionPolicy Bypass -File D:\Kundi\infra\scripts\typed-v2-telegram-notify.ps1 `
  -Workspace D:\Kundi `
  -SnapshotJson D:\Kundi\reports\typed_v2_monitoring_snapshot.json
```
3. If send fails:
- do not change rollout stage automatically
- continue manual decision using snapshot JSON/MD
- record delivery failure in stage decision card
