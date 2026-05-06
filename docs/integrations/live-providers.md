# Live Providers Hookup Guide

## Supported modes
- `deterministic` / `mock`
  - local/staging baseline without external dependency.
- `http`
  - production-style integration through HTTP adapters.

## LLM
- mode: `AI_LLM_PROVIDER`
- required for `http` mode:
  - `AI_LLM_BASE_URL`
  - `AI_LLM_API_KEY`

## TTS
- mode: `AI_TTS_PROVIDER`
- required for `http` mode:
  - `AI_TTS_BASE_URL`
  - `AI_TTS_API_KEY`

## WhatsApp
- mode: `WHATSAPP_PROVIDER`
- required for `http` mode:
  - `WHATSAPP_BASE_URL`
  - `WHATSAPP_API_TOKEN`

## Provider health/status abstraction
- API readiness (`/readyz`) reports provider status:
  - `ready`: live config present
  - `mock`: deterministic mode
  - `misconfigured`: live mode selected but required env is missing

## Safe behavior when secrets are missing
- Bootstrap falls back to deterministic provider behavior to keep service alive.
- `/readyz` remains `degraded` while provider config is `misconfigured`.
- This prevents false "live-ready" claims.

## First live hookup checklist
1. Switch mode to `http`.
2. Fill base URL + API key/token in staging secrets.
3. Verify `/readyz` provider state transitions from `misconfigured` to `ready`.
4. Run staging smoke tests for assistant + WhatsApp slices.
