# Kundi Assistant Child Safety Baseline

## Scope

This pass hardens the existing authenticated `POST /v1/assistant/message` backend path. It does not expose Assistant in Home or mobile navigation, add academic context, change academic ingest/read contracts, change Kundi behavior, implement TTS/STT, persist conversations, or create automatic parent/emergency escalation.

The public request and response field set is unchanged. Invalid modes, malformed history, and invalid grade levels are now rejected instead of being silently repaired. A safety intervention uses the existing Assistant response package and `pedagogy_flags.safety_intervention`; no new public JSON field was added.

## Safety categories and risk levels

Typed categories are:

- `self_harm`
- `violence_or_abuse`
- `bullying`
- `sexual_safety`
- `dangerous_or_illegal`
- `medical_high_stakes`
- `privacy_or_secrets`
- `harassment`
- `unknown_risk`

The policy distinguishes informational/educational content, harmful/actionable content, and an immediate safety concern. Ordinary school questions about health, wars, chemistry, or related subjects are not blocked merely because they mention a sensitive subject.

## Input limits and validation

Defaults are conservative and configurable through the existing backend environment configuration:

| Limit | Default | Environment variable |
|---|---:|---|
| Request body | 64 KiB | named code limit |
| Current message | 4,000 Unicode code points | `AI_ASSISTANT_MAX_TEXT_RUNES` |
| History messages | 20 | `AI_ASSISTANT_MAX_HISTORY_MESSAGES` |
| One history message | 4,000 Unicode code points | `AI_ASSISTANT_MAX_HISTORY_MESSAGE_RUNES` |
| Total history | 12,000 Unicode code points | `AI_ASSISTANT_MAX_HISTORY_RUNES` |

Accepted modes are `tutor` and `general_chat`. Grade level `0` retains the existing default of grade 7; otherwise the accepted school-domain range is 1 through 12. History roles are restricted to `user` and `assistant`, and empty/invalid UTF-8 history entries are rejected. Authentication remains the source of the student identifier; the JSON body cannot override it.

## Input moderation

The provider-independent `safety.Moderator` interface currently uses a deterministic `Policy`. It applies NFKC Unicode normalization, case folding, and whitespace/punctuation normalization, then checks a deliberately small set of obvious high-risk phrases in Russian, Kazakh, and English. Current user input and supplied history are checked before the LLM.

Ambiguous content is allowed rather than aggressively blocked. This deterministic baseline is not a production-complete classifier and is not expected to detect all paraphrases, obfuscation, coded language, or context-dependent risk. A production moderation provider can implement the same interface without rewriting the Assistant service.

## Output moderation and safe responses

Every provider response, including the stable provider-failure fallback, passes through `OutputValidator` before it can reach the client, TTS, or avatar cue generation. Unsafe or uncheckable output is replaced by `SafeResponseFactory`; it never reaches TTS and produces no emotional/gesture/viseme cues.

Safety responses are short, calm, non-accusatory, and localized to Russian, Kazakh, or English when detected. Immediate-concern responses ask the child to contact a trusted adult and, if danger is immediate, local emergency services. Kundi never claims that it contacted a parent or emergency service.

LLM calls have a configurable service timeout (`AI_ASSISTANT_LLM_TIMEOUT_SEC`, default 28 seconds); the initial Gemma primary deadline is 25 seconds. Timeout, provider 4xx, provider 5xx, malformed response, moderation failure, cancellation, and internal failure are logged as sanitized typed result/error codes. The client receives stable safe text, and there are no automatic retries.

## Privacy and logging

Assistant telemetry contains only bounded operational dimensions: result, controlled error kind, provider/model, normalized locale, mode, fallback flag, tutoring intent, safety category, latency, and counts. Student/session/account identifiers, stable user hashes, prompts, responses, history, transcripts, tokens, authorization values, provider request IDs, endpoints, and free-form error strings are not logged or used as metric tags. The existing AI worker audit records lengths and non-content metadata only.

This pass does not add conversation persistence or academic context to LLM payloads.

## Rate limiting

The authenticated HTTP path uses a bounded fixed-window limiter keyed by authenticated student UUID, never by IP alone. Defaults are:

- 20 requests per 60 seconds (`AI_ASSISTANT_RATE_LIMIT`, `AI_ASSISTANT_RATE_WINDOW_SEC`)
- at most 10,000 tracked identities (`AI_ASSISTANT_RATE_MAX_IDENTITIES`)

Expired entries are cleaned and the oldest entry is evicted at the bound. A limited request returns typed HTTP 429 `assistant_rate_limited` and does not call LLM or TTS.

The limiter is in memory and per backend process. It is not a global production quota and becomes approximate when multiple API instances are running. A shared production limiter would be required when horizontal scaling makes a global quota necessary.

## Audio URL policy

Returned audio URLs must parse successfully, use HTTPS, contain no user info, and have an exact hostname allowed by the configured trusted-host list or configured TTS provider base URL. Localhost, loopback, private/link-local IP addresses, and common local/private DNS suffixes are rejected. Invalid audio makes only audio/cues unavailable; safe text is preserved. The backend does not fetch the returned audio URL.

`AI_TTS_TRUSTED_HOSTS` may add comma-separated exact hosts. Trusting a hostname does not override the local/private-host rejection. The current placeholder `cdn.kundi.local` is intentionally rejected, so the default deterministic TTS produces `audio_status=unavailable` until a public trusted HTTPS host is configured. DNS resolution/rebinding validation is not performed; production should use a tightly controlled provider allowlist.

## Known limitations and unresolved product decisions

Not implemented in this pass: production LLM or moderation selection, real TTS, microphone/STT, persistence, global distributed quota, automatic retries, academic context, parent/emergency notifications, mobile rollout, or AssistantPage exposure.

The following product decisions remain unresolved and must be approved separately:

- conversation retention and deletion policy;
- parent visibility and child privacy boundaries;
- approved academic context and consent rules;
- production LLM provider;
- production moderation provider and human review operations;
- Kazakhstan-specific emergency/escalation UX and localized guidance;
- TTS privacy, retention, and audio storage;
- Assistant rollout flag and release criteria.
