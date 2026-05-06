# Kundi Architecture README

## Top-level domains
- `backend/`: Go modular monolith with stateless API/workers and PostgreSQL source of truth.
- `mobile/`: Flutter feature-first app with Riverpod, SQLite canonical cache, secure storage.
- `avatar_unity/`: Unity runtime module for avatar playback/lipsync/emotion/gesture boundaries.
- `infra/`: local/deploy scaffolding.
- `docs/`: architecture, migration, contracts, and audit notes.

## Verified runtime principles
- Diary anti-bot/session flows are mobile-only.
- Backend accepts canonical ingest bundles only (no backend diary parser).
- Ingest idempotency includes checksum conflict detection.
- Jobs use Postgres queue, lease reclaim, bounded retries, and dead-letter state.
- Avatar access from Flutter is through facade/bridge contracts only.

## Honest maturity snapshot
- Production-strong foundation:
  - migrations + tracked migration history,
  - auth login + refresh flow,
  - ingest merge transaction + idempotency handling,
  - jobs retry/backoff/lease reclaim baseline,
  - worker execution baselines for jobs/whatsapp/ai,
  - mobile canonical cache + sync queue baseline.
- Partial / still skeleton:
  - several backend domain modules (`guardians`, `media`, `analytics`, etc.),
  - Dnevnik.ru and EduPage connectors (explicit stubs),
  - full real-provider integrations (LLM/TTS/WhatsApp) with live secrets.

See `GAP_AUDIT.md` and `IMPLEMENTATION_DEPTH_PLAN.md` for prioritized remaining depth.
