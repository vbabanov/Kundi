# Runbook: Staging Deploy

## Goal
Bring up a reproducible staging environment with:
- PostgreSQL
- Object storage (MinIO-compatible)
- Backend API
- Worker jobs
- Worker AI
- Worker WhatsApp

## Prerequisites
1. Docker + Docker Compose (or Kubernetes access for `infra/k8s/staging`).
2. Filled secrets in `infra/env/backend.staging.env`.
3. `FIELD_ENCRYPTION_KEY` exactly 32 bytes.
4. Docker daemon must be running (`docker info` succeeds).

## Preflight checks
1. `docker info`
2. `docker compose version`
3. Check local port conflicts if deploying on a shared host:
   - `5432`, `8080`, `9000`, `9001`
4. If ports are occupied, use host port overrides:
   - `STAGING_POSTGRES_HOST_PORT`
   - `STAGING_API_HOST_PORT`
   - `STAGING_MINIO_API_HOST_PORT`
   - `STAGING_MINIO_CONSOLE_HOST_PORT`

## Docker path (recommended first staging pass)
1. Copy:
   - `infra/env/backend.staging.env.example` -> `infra/env/backend.staging.env`
2. Fill secrets and provider mode values.
3. Run:
   - `powershell -ExecutionPolicy Bypass -File infra/scripts/staging-up.ps1`
   - Optional with host-port overrides:
     - `$env:STAGING_POSTGRES_HOST_PORT='5433'`
     - `$env:STAGING_API_HOST_PORT='8081'`
     - `docker compose -f infra/docker/docker-compose.staging.yml --project-name kundi-staging up -d --build`
4. Verify:
   - `GET http://localhost:8080/healthz` should return 200.
   - `GET http://localhost:8080/readyz` should return:
     - `ready` for db + provider config sanity,
     - `degraded` when provider live mode is selected but secret/base URL is missing.

## Migration strategy
- Use dedicated `migrator` job/container (`backend/cmd/migrator`) before app/workers.
- Keep `DB_AUTO_MIGRATE=false` for API/workers in staging.

## Rollback basics
1. Stop stack:
   - `powershell -ExecutionPolicy Bypass -File infra/scripts/staging-down.ps1`
2. Revert env values or image tags.
3. Re-run migrator only after schema rollback plan is validated.

## Notes
- Deterministic provider mode is allowed in staging for initial smoke.
- Live provider mode requires secrets and endpoint reachability.
