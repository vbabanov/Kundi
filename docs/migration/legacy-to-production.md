# Legacy to Production Migration Notes

## Policy (enforced)
- `legacy/*` is reference-only.
- New implementation is only in `backend/`, `mobile/`, `avatar_unity/`, `infra/`, `docs/`.
- No “lift-and-shift” of legacy architecture.

## What is migrated in principle
1. Mobile-side diary bootstrap and anti-bot direction.
2. Canonical ingest bundle approach.
3. Tutor/avatar response shape (`text/audio/visemes/emotion/gesture/pedagogy`).
4. WhatsApp workflow intent (digest/photo dispatch).

## What is explicitly not migrated as-is
1. Legacy backend parser runtime and mixed worker/API process model.
2. Legacy page-centric mobile orchestration.
3. Legacy avatar coupling to UI internals.

## Current migration reality
- Foundation migrated and running:
  - backend schema/migrations/idempotent ingest/jobs/auth,
  - mobile canonical cache/sync queue,
  - connector + avatar + AI contract boundaries.
- Still incomplete migration depth:
  - full provider-grade connectors (Dnevnik/EduPage missing),
  - non-shell implementation for several backend domain modules,
  - production integrations for external providers.

## Cutover guardrails
- Keep legacy data snapshots for audit only.
- Replay ingest bundles into canonical schema for backfill.
- Use feature flags for assistant/avatar and worker expansion.
- Keep rollback path: disable workers while retaining ingest persistence.

