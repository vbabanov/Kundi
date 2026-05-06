# Staging Config Matrix

## Backend env sources
- `backend/.env.staging.example` (developer reference)
- `infra/env/backend.staging.env.example` (compose-ready template)
- `infra/k8s/staging/backend-configmap.yaml` + `backend-secrets.template.yaml`

## Critical vars
- Security:
  - `ACCESS_TOKEN_SECRET`
  - `FIELD_ENCRYPTION_KEY` (32 bytes)
- DB:
  - `DATABASE_URL`
  - `DB_AUTO_MIGRATE=false` for all long-lived services
- Providers:
  - `AI_LLM_PROVIDER`, `AI_LLM_BASE_URL`, `AI_LLM_API_KEY`
  - `AI_TTS_PROVIDER`, `AI_TTS_BASE_URL`, `AI_TTS_API_KEY`
  - `WHATSAPP_PROVIDER`, `WHATSAPP_BASE_URL`, `WHATSAPP_API_TOKEN`
- Object storage:
  - `OBJECT_STORAGE_ENDPOINT`, `OBJECT_STORAGE_BUCKET`, access keys

## Provider mode policy
- `deterministic` / `mock`:
  - safe baseline for smoke runs without external secrets.
- `http`:
  - requires base URL + API key/token.
  - readiness reports `misconfigured` if required values are missing.

## Mobile config strategy
- use dart-define JSON files:
  - `mobile/env/dart_define.dev.example.json`
  - `mobile/env/dart_define.staging.example.json`
- run examples:
  - `flutter run --dart-define-from-file=env/dart_define.dev.example.json`
  - `flutter run --dart-define-from-file=env/dart_define.staging.example.json`
