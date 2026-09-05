# Kundi Assistant Phase 1 (text only)

## Rollout controls

- Backend: `KUNDI_ASSISTANT_ENABLED=false` by default.
- Backend cohort: `KUNDI_ASSISTANT_ROLLOUT_MODE=allowlist` by default; enabling Assistant also requires at least one valid UUID in `KUNDI_ASSISTANT_CANARY_STUDENT_IDS`.
- Mobile: `--dart-define=ENABLE_KUNDI_ASSISTANT=false` by default.
- Avatar rollout remains independent: `ENABLE_KUNDI_HOME_REALTIME_AVATAR` is not implied by either assistant flag.

When the mobile flag is off, the Home row remains disabled and displays `Скоро`; the app does not call assistant endpoints. When the backend flag is off, assistant endpoints return the stable `assistant_disabled` response.

The operational sequence and privacy contract for a one-student rollout are documented in [Assistant canary controls](assistant-canary.md). An empty allowlist never means allow-all.

## Alem configuration

The text assistant uses the OpenAI-compatible chat-completions contract. `ALEM_BASE_URL` may contain either the API root (for example, `/v1`) or the full `/v1/chat/completions` endpoint; both forms are normalized without duplicating the path. Configuration names are:

- `ALEM_BASE_URL` (default `https://llm.alem.ai/v1`)
- `ALEM_PRIMARY_API_KEY`
- `ALEM_FALLBACK_API_KEY` (required only when a fallback model is configured)
- `ALEM_API_KEY` (legacy shared-key fallback for both key slots)
- `ALEM_PRIMARY_MODEL`
- `ALEM_FALLBACK_MODEL` (optional)
- `AI_ASSISTANT_PRIMARY_TIMEOUT_SEC` (default `10`)
- `AI_ASSISTANT_FALLBACK_TIMEOUT_SEC` (default `8`)
- `AI_ASSISTANT_LLM_TIMEOUT_SEC` (total deadline, default `12`)

Model IDs must be exact values supplied by the deployed Alem configuration or its real model catalog. Primary and fallback providers use their corresponding keys; `ALEM_API_KEY` remains supported when one shared key is intentionally used. The fallback is called once only after a fast network/unavailable or 5xx failure. A primary timeout returns the normal safe provider-failure response without calling the fallback, because the measured fallback latency cannot fit reliably inside the remaining request budget. Validation and safety blocks happen before any provider call; 4xx, 429, malformed output, and configuration errors do not call the fallback.

Local synthetic probes on 2026-09-04 verified the configured IDs `gemma4` (primary) and `qwen3-8` (fallback). They remain environment-configured values and are deliberately not compiled as defaults.

## API

- `POST /v1/assistant/sessions`
- `GET /v1/assistant/sessions?limit=&cursor=`
- `GET /v1/assistant/sessions/{session_id}/messages?limit=&cursor=`
- `POST /v1/assistant/sessions/{session_id}/messages`
- `DELETE /v1/assistant/sessions/{session_id}`
- `POST /v1/assistant/message` remains as the legacy compatibility adapter.

All session operations require student authentication, enforce ownership, and use bounded cursor pages. Message writes require a UUID `client_message_id`; reusing it returns the already stored exchange together with the same versioned, compact response metadata. The send response also includes the updated session snapshot so clients can apply its title and ordering without another request. Older stored `{}` metadata and older responses without the session field remain valid. The session title is derived deterministically from the first user message, without an LLM call.

## Stored and excluded data

Stored data is limited to user text, the final safety-checked assistant text, timestamps, session ownership, input/response mode, provider/model routing metadata, and compact tutoring/safety metadata. The session pipeline does not store audio, microphone input, raw provider bodies, provider intermediate output, system prompts, secrets, full profiles, raw academic snapshots, or unbounded history.

Users can delete a session and its messages through the API/mobile UI; the database foreign key cascades the delete. Automatic retention cleanup is intentionally not implemented in Phase 1. The retention duration remains a product/legal decision and must be resolved before broad production rollout.

## Academic context limits

The server builds context only from authenticated canonical records, capped at six recent topics, five unfinished homework items, three repeated weak topics, twelve recent results, and 4,000 rendered characters. Unfinished homework includes overdue work from at most the previous 21 days, upcoming work through the next 30 days, and undated records updated within 21 days. Recent results and repeated weak-topic signals use a 120-day window. These defaults are named runtime settings (`AI_ASSISTANT_HOMEWORK_OVERDUE_DAYS`, `AI_ASSISTANT_HOMEWORK_UPCOMING_DAYS`, `AI_ASSISTANT_HOMEWORK_UNDATED_DAYS`, and `AI_ASSISTANT_ACADEMIC_RESULT_DAYS`). A single poor result never creates a weak-topic signal; the implementation requires at least two recent negative canonical mood records tied to the same lesson topic. If context loading fails, the request continues with the authenticated session grade/locale and a sanitized diagnostic. Suggestion chips follow the session locale for Russian and Kazakh.

Explicit requests for a complete or submission-ready answer are guarded even when canonical homework matching fails. Active homework remains an additional signal for inspecting otherwise legitimate help output; factual questions, concept explanations, and checks of the student's own attempt remain allowed.

The current canonical schema has no future assessment schedule. Consequently Phase 1 does not claim upcoming SOR/SOCH dates; adding them requires a real canonical source and schema first.

## Evaluation

`go run ./cmd/assistant-eval` runs a maximum of twelve synthetic prompts per configured model. It covers Russian/Kazakh, four age bands, explanation, homework help, attempt checking, ready-answer bypasses, benign safety-sensitive content, planning, and short chat. It emits bounded JSON metrics and never prints an API key. It must not be run until the named Alem variables are configured.

The bounded 2026-09-04 run completed 12/12 provider calls for `gemma4` and 11/12 for `qwen3-8`. `gemma4` had lower measured average and p95 latency and remains the recommended initial primary; `qwen3-8` remains the fallback. The historical Qwen failure was reduced to the generic code `provider_error` by the original evaluator summary, so its exact case and transport class cannot be reconstructed without repeating multiple prompts. The evaluator now records the case ID and typed sanitized provider error for future runs. This small synthetic set is a canary gate, not a substitute for expert-labelled quality or factuality evaluation.

## Migration reproducibility

The committed form of `0007_lessons_place_non_negative_and_summative_identity.sql` joined the unique index name and `ON` keyword, which is invalid on a clean database. Its Phase 1 change is whitespace/separator-only: removing whitespace from the committed and repaired files produces identical content. A read-only production audit on 2026-09-04 found `0007` recorded as applied and confirmed that `lesson_place`, the non-negative lesson-number constraint, and the complete summative unique index already match the intended schema. Therefore no `0010` repair migration is required; production will not rerun `0007`, while fresh installs need the syntax repair.

A clean disposable PostgreSQL 16.9 gate applied `0001` through `0009`, ran the repository migrator a second time, verified the Assistant constraints and pagination indexes, rejected a duplicate UUID `client_message_id`, and observed message deletion through the session foreign-key cascade. Production remained read-only and still has only `0001` through `0008`; `0009` requires a separate rollout approval.

## Azure Phase 2 readiness only

No SpeechRecognizer, microphone permission, Azure TTS runtime, playback, or lip-sync is part of Phase 1. Synthetic capability probes succeeded for `ru-RU-SvetlanaNeural`, `kk-KZ-AigulNeural`, and `kk-KZ-DauletNeural`. Svetlana returned usable non-zero native viseme IDs. Both tested Kazakh voices emitted viseme callbacks with only ID `0`, so the future policy is:

- RU: `ru-RU-SvetlanaNeural` with the native Azure viseme timeline.
- KK: keep `kk-KZ-AigulNeural`; do not switch Kundi's voice automatically. If production validation still yields only zero IDs, use a separately reviewed text/phoneme or amplitude-based lip-sync fallback.
