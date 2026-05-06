# Infra Deployment Guide

`infra/` contains staging deployment scaffolding for local Docker and Kubernetes-style staging clusters.

## Structure
- `docker/`
  - `docker-compose.yml`: local dev infra (postgres + minio).
  - `docker-compose.staging.yml`: full staging stack (postgres, minio, migrator, api, workers).
- `env/`
  - `backend.staging.env.example`: staging env template for backend services.
  - `typed-v2-monitoring.env.example`: typed v2 monitoring loop env template (Telegram + runtime paths).
- `k8s/staging/`
  - namespace, configmap, secrets template, postgres/minio workloads, backend api/workers, migrator job.
- `scripts/`
  - `dev-up.ps1`
  - `staging-up.ps1`
  - `staging-down.ps1`
  - `typed-v2-stage0-smoke.ps1`
  - `typed-v2-telemetry-extract.ps1`
  - `typed-v2-monitoring-snapshot.ps1`
  - `typed-v2-telegram-notify.ps1`
  - `typed-v2-backend-monitoring-snapshot.py`
  - `typed-v2-telegram-notify.py`
  - `typed-v2-monitoring-loop.sh`
- `systemd/`
  - `kundi-typed-v2-monitor.service`
  - `kundi-typed-v2-monitor.timer`

Recommended Linux server location for these ops scripts:
- `/root/kundi-prod/shared/ops/typed-v2/`

## Staging startup (Docker Compose)
1. Copy `infra/env/backend.staging.env.example` to `infra/env/backend.staging.env`.
2. Fill secrets and provider variables.
3. Run:
   - `powershell -ExecutionPolicy Bypass -File infra/scripts/staging-up.ps1`
4. Verify:
   - API health: `GET http://localhost:8080/healthz`
   - API readiness: `GET http://localhost:8080/readyz`

## Migration strategy
- Dedicated `migrator` service runs `backend/cmd/migrator`.
- Other binaries run with `DB_AUTO_MIGRATE=false` in staging.
- This avoids concurrent migration attempts during rollout.

## Secrets policy
- Keep real secrets outside git.
- Use placeholders from:
  - `backend/.env.staging.example`
  - `infra/env/backend.staging.env.example`
  - `infra/k8s/staging/backend-secrets.template.yaml`

Typed v2 notification (optional per runtime profile):
- `KUNDI_TYPED_V2_TELEGRAM_BOT_TOKEN`
- `KUNDI_TYPED_V2_TELEGRAM_CHAT_ID`

Typed v2 monitoring loop runtime (Linux/systemd):
- `KUNDI_TYPED_V2_MONITOR_WORKSPACE`
- `KUNDI_TYPED_V2_MONITOR_UNIT`
- `KUNDI_TYPED_V2_MONITOR_SINCE`
- `KUNDI_TYPED_V2_MONITOR_OUTPUT_JSON`
- `KUNDI_TYPED_V2_MONITOR_OUTPUT_MD`
