# Phase 2 Architecture Boundaries and Ownership

## Product-level boundaries
- Mobile owns source-specific diary runtime, anti-bot session behavior, and canonical bundle construction.
- Backend owns canonical persistence, merge/idempotency, derived analytics, AI orchestration, WhatsApp dispatch, and jobs.
- Avatar runtime owns 3D state machine, animation/lip-sync/emotion/gesture playback under Unity runtime.

## Backend ownership by module
- `auth`: access + refresh lifecycle, token validation.
- `students`, `guardians`, `profiles`: identity and relationship context.
- `diary_ingest`: canonical ingest validation, idempotency, merge orchestration.
- `academic`, `attendance`, `homework`, `grades`: domain records and read models.
- `assistant`, `persona`: tutor/general-chat orchestration, pedagogy + persona policy, avatar cues.
- `jobs`: lease-based execution model, retries, dead-letter semantics.
- `whatsapp`: outbound parent workflows.
- `analytics`, `audit`: derived stats, audit trail.

## Mobile ownership by layer
- `presentation`: widgets/screens only, no source payload logic.
- `application`: use-cases + orchestrators + Riverpod controllers.
- `domain`: pure entities/value objects/use-case contracts.
- `data`: repositories + DTO mappers + local/remote datasource adapters.

## Connector runtime boundary
- Exposes `DiaryConnector` contract only.
- Contains source adapters, anti-bot/session orchestration, and raw payload diagnostics.
- UI must consume canonical models only; raw payload is never surfaced to feature UI.

## Avatar boundary
- Flutter calls only `AvatarFacade` commands/events.
- No Flutter feature page can call Unity/native internals directly.
- Response package from backend assistant is mapped into avatar commands by facade.

## Cross-cutting runtime constraints
- Stateless API and workers.
- PostgreSQL as source of truth.
- Idempotent ingest and idempotent job processing.
- Sensitive credentials are not stored in plaintext outside secure mobile storage.
