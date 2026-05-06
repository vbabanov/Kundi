# Provider Adapters Status

## Implemented adapters
- LLM:
  - `deterministic` provider for local/dev deterministic behavior.
  - `http` provider contract for real external endpoint hookup.
- TTS:
  - deterministic URL renderer provider.
  - `http` provider contract for real external synthesis endpoint.
- WhatsApp:
  - deterministic provider for job-flow testing.
  - `http` provider contract for real dispatch endpoint.

## Config wiring
- AI:
  - `AI_LLM_PROVIDER`, `AI_LLM_BASE_URL`, `AI_LLM_API_KEY`
  - `AI_TTS_PROVIDER`, `AI_TTS_BASE_URL`, `AI_TTS_API_KEY`
- WhatsApp:
  - `WHATSAPP_PROVIDER`, `WHATSAPP_BASE_URL`, `WHATSAPP_API_TOKEN`

## Truthfulness status
- Working now:
  - deterministic providers and full orchestration paths through contracts.
  - readiness provider-status abstraction (`/readyz`) with `ready/mock/misconfigured` states.
- Pending external hookup:
  - real provider credentials/secrets,
  - production endpoint hardening (timeouts, auth scheme specifics, throttling contracts),
  - provider-specific observability and SLA enforcement.
