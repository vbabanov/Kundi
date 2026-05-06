# Deployment README (Staging Path)

## Latest execution evidence
- See `STAGING_DEPLOY_EXECUTION.md` for real commands and outcomes.
- If Docker daemon is unavailable, deployment is considered blocked and not deployed.

## Recommended order
1. Provision infrastructure (Postgres + object storage).
2. Apply secrets/config.
3. Run migrator.
4. Deploy API.
5. Deploy workers (`worker_jobs`, `worker_ai`, `worker_whatsapp`).
6. Run smoke plan.

## Artifacts
- Docker staging stack:
  - `infra/docker/docker-compose.staging.yml`
- Kubernetes staging scaffolding:
  - `infra/k8s/staging/*.yaml`
- Runbooks:
  - `docs/runbooks/staging-deploy.md`
  - `docs/runbooks/jobs-and-dispatch.md`

## Health checks
- Liveness: `/healthz`
- Readiness: `/readyz`
  - includes DB check
  - includes provider configuration status (`ready`, `mock`, `misconfigured`)
