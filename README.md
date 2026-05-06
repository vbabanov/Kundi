# Kundi Production Rebuild

This repository contains:
- `legacy/` as reference-only implementation.
- New production architecture in `backend/`, `mobile/`, `avatar_unity/`, `infra/`, `docs/`.

Primary architecture docs:
- `docs/legacy/legacy-analysis.md`
- `docs/architecture/repo-tree.md`
- `docs/architecture/boundaries.md`
- `docs/migration/legacy-to-production.md`

Verification and depth artifacts:
- `VERIFIED_REPO_TREE.md`
- `VERIFIED_TEST_REPORT.md`
- `VERIFIED_EXECUTION_REPORT.md`
- `INTEGRATION_TEST_PLAN.md`
- `GAP_AUDIT.md`
- `IMPLEMENTATION_DEPTH_PLAN.md`
- `P0_EXECUTION_PLAN.md`

Current status:
- Architecture boundaries are in place and verified.
- Backend ingest/auth/jobs foundations are implemented and tested.
- Worker baselines are operational (`worker_jobs`, `worker_whatsapp`, `worker_ai`) with module-owned handlers.
- Mobile canonical cache and sync queue run on SQLite with Riverpod state access.
- Mobile assistant slice is wired to backend assistant API and avatar facade package contract.
- Kundelik connector has retry-safe transport + typed diagnostics, but still not full provider-complete parser parity.
- External provider integrations (LLM/TTS/WhatsApp) have clean adapters and config wiring; production secrets/hooks remain pending.
- A subset of backend/mobile features remains shell-level and is explicitly tracked in `GAP_AUDIT.md`.
