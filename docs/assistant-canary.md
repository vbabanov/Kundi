# Assistant one-student canary controls

This document is the operating contract for the active one-student, text-only Assistant canary. It does not authorize cohort expansion. The last accepted source before the wider-readiness work was `2c6abda7a899856fad247e84b49223d57a8d015b`; every production report must replace that baseline with the effective deployed source SHA.

## Access controls

`KUNDI_ASSISTANT_ENABLED` remains the master switch and defaults to `false`. The allowlist cannot enable Assistant by itself.

`KUNDI_ASSISTANT_ROLLOUT_MODE` accepts exactly:

- `allowlist` (default): when Assistant is enabled, `KUNDI_ASSISTANT_CANARY_STUDENT_IDS` must contain at least one valid comma-separated student UUID. Values are trimmed and deduplicated. An empty or malformed list is a startup configuration error.
- `all`: explicitly permits every authenticated student while the master switch is enabled. This mode must never be inferred from an empty allowlist.

Student UUIDs are access-control data. Do not place real UUIDs in examples, documentation, source control, logs, metric tags, screenshots, or tickets.

The gate runs at the Assistant service boundary before repository, rate-limit, LLM, or speech-token work for:

- legacy message requests;
- session create/list/delete;
- session message list/send;
- speech authorization.

An authenticated student outside the cohort receives HTTP 404 with code `assistant_unavailable`. The response does not disclose that an allowlist exists. Internal Assistant jobs that call the same service inherit the gate.

## Readiness contract

When Assistant is enabled in `allowlist` mode, readiness requires both a non-empty parsed allowlist and an observability mode other than `off`, `none`, or `noop`. An invalid rollout mode or malformed UUID list is fail-closed. Readiness reasons must not include UUID values, secrets, or the number of cohort members.

The initial one-student canary is primary-only and uses `gemma4`. The bounded Kazakh-language candidate evaluation did not qualify `qwen3-8` as either the primary model or the initial canary fallback: it had one malformed empty response, two `finish_reason=length` responses, and higher latency in every completed pair. Qwen support remains in the code for a future re-evaluation; it is not enabled by this plan.

The Alem configuration contract for this canary is:

- required: `ALEM_BASE_URL`, `ALEM_PRIMARY_API_KEY`, and `ALEM_PRIMARY_MODEL=gemma4`;
- primary-only: both `ALEM_FALLBACK_MODEL` and `ALEM_FALLBACK_API_KEY` are absent;
- Gemma completion budget: `max_tokens=1400`;
- timeout contract: `AI_ASSISTANT_PRIMARY_TIMEOUT_SEC=25`, `AI_ASSISTANT_LLM_TIMEOUT_SEC=28`, and unchanged `AI_ASSISTANT_FALLBACK_TIMEOUT_SEC=8`;
- optional future fallback: model and key must either both be present or both be absent. Supplying only one is a readiness error.

An empty fallback model means there is no secondary provider. A timeout remains terminal and is not fallback-eligible. The existing fallback implementation is otherwise unchanged and may only run after a provider 5xx or network/unavailable failure when a complete fallback pair is configured.

When Assistant is disabled, the existing readiness behavior is unchanged.

## No-PII observability

The canary uses both structured log hooks and a loopback-only Prometheus exporter. Assistant terminal outcomes are emitted once per service operation through `assistant_requests_total` and `assistant_latency_ms`. Every service metric has a bounded `operation` tag. Session CRUD has `provider=none`, `model=none`, and does not count as generation. Speech authorization emits both its service outcome and its existing issuance count/latency and rate-limit counter.

Each actual LLM call emits exactly one logical `assistant_generation_requests_total` and `assistant_generation_latency_ms`. Provider attempts additionally emit `assistant_generation_attempts_total` and `assistant_generation_attempt_latency_ms`, with at most primary and fallback attempts. Generation success is separate from later service outcomes such as the ready-answer guard.

Tags are restricted to controlled values for result, error kind, operation, provider, model, execution stage, finish reason, normalized locale (`ru`, `kk`, or `other`), mode, fallback attempted/succeeded state, bounded primary failure category, tutoring intent, and safety category. Unknown model names map to `unknown`. Do not add identifiers, raw content, credentials, endpoints, provider request IDs, reasoning content, or free-form errors.

Prometheus persists the six approved Assistant families across API and metrics-service restarts. Both exporter and Prometheus listeners are loopback-only; Caddy has no metrics route. See `docs/assistant-observability.md` for retention, privacy checks, queries, and rollback. Mobile crash/ANR delivery remains a separate external prerequisite.

## Safe change sequence

The configuration values below are illustrative; replace the placeholder only in the approved secret/configuration system, never in source control:

```text
KUNDI_ASSISTANT_ENABLED=false
KUNDI_ASSISTANT_ROLLOUT_MODE=allowlist
KUNDI_ASSISTANT_CANARY_STUDENT_IDS=<approved-student-uuid>
ALEM_BASE_URL=<approved-alem-base-url>
ALEM_PRIMARY_API_KEY=<approved-primary-secret-reference>
ALEM_PRIMARY_MODEL=gemma4
AI_ASSISTANT_PRIMARY_TIMEOUT_SEC=25
AI_ASSISTANT_LLM_TIMEOUT_SEC=28
AI_ASSISTANT_FALLBACK_TIMEOUT_SEC=8
# ALEM_FALLBACK_MODEL is absent
# ALEM_FALLBACK_API_KEY is absent
```

Before any future deployment or configuration change:

1. Confirm the release commit and all required CI jobs are successful.
2. Verify the approved UUID is stored only in the protected runtime configuration.
3. Verify migrations and rollback/backup prerequisites separately; this change does not apply migrations.
4. Verify observability is enabled and that logs contain no synthetic privacy markers.
5. Preserve the existing protected canary env and `30-assistant-canary.conf`; never replace allowlist mode with `all` during troubleshooting.
6. Exercise allowed and denied accounts, then inspect bounded outcome and latency metrics.

Release rollback switches only the API release symlink to the last accepted artifact and restarts the API while preserving the canary env/drop-ins. Canary deactivation removes only `30-assistant-canary.conf`, reloads systemd, and restarts the API. Do not switch to `all` as a troubleshooting shortcut.

## Prerequisite status model

Status means:

- `CLOSED`: implemented and verified in the current production acceptance.
- `OPEN-LOCAL`: can be completed without a new account, credential, subscription, signing identity, or product decision.
- `OPEN-EXTERNAL`: requires such an external input and must not be reported as complete.
- `NOT-REQUIRED`: deliberately outside the one-student text canary contract.

| Prerequisite | State | Acceptance evidence |
| --- | --- | --- |
| Gemma4 model, `1400` max tokens, 25/28s timeout, no fallback | CLOSED | Targeted RU/KK provider and production suites; effective readiness contract |
| Reproducible Linux backend artifact and migrations 0001–0011 | CLOSED | Canonical stable workflow, two independent builds, Linux migrator rehearsal |
| Durable bounded Assistant metrics | CLOSED | Loopback exporter, local persistent Prometheus, restart-persistence and privacy checks |
| Caddy/privacy boundary | CLOSED | No Caddy access log, no metrics route, public `/metrics` denied, bounded journal scan |
| Production secret file protection | CLOSED | Root ownership and mode `0600`; values never included in reports |
| Automated local backup and restore rehearsal | CLOSED | Daily atomic custom-format dump, checksum, retention, and isolated PostgreSQL restore/migrate rehearsal |
| Off-host encrypted backup custody | OPEN-EXTERNAL | Storage destination, encryption key custody, retention policy, and restore owner decision |
| Mobile crash/ANR code path | CLOSED | Sentry Flutter integration, Android ANR enabled, privacy scrubber tests, release-only production gate |
| Mobile crash/ANR delivery | OPEN-EXTERNAL | Separate production Sentry project/DSN and a received synthetic crash plus ANR on a release build |
| Android unsigned release compile and no-debug-sign policy | CLOSED | CI release AAB compile and Gradle signing-policy gate |
| Permanent Android release identity | OPEN-EXTERNAL | Approved identity/custody, certificate fingerprint, signed AAB verification |
| Manual stable governance | CLOSED | Feature CI, ff-only stable integration, stable CI, canonical artifact |
| Enforced GitHub branch protection | OPEN-EXTERNAL | Current private-repository plan rejects branch protection/rulesets; upgrade or repository policy change required |
| Voice Input, TTS, fallback, and `worker_ai` | NOT-REQUIRED | They remain off/absent/inactive for this text-only canary |
| `dispatch_whatsapp` dead-letter backlog | NOT-REQUIRED | Separate operational backlog; do not mutate it during Assistant acceptance |

## Objective real-user soak gate

Do not expand the cohort until every `OPEN-EXTERNAL` item designated by the release owner as required for mobile distribution is closed and one uninterrupted observation window satisfies all criteria below:

1. At least seven consecutive days, at least 50 real generation requests across at least three separate days, and at least 10 requests for each rollout locale being evaluated. Low traffic extends the soak; it does not convert missing evidence into a pass.
2. Health and readiness remain available with no unexplained interval longer than two minutes; the effective source/configuration is unchanged throughout the measured window.
3. Generation success rate is at least 95%; timeout rate is at most 2%; malformed and incomplete totals are zero; successful provider responses have `finish_reason=stop`.
4. RU and KK generation p50 are at most 10 seconds and p95 at most 20 seconds. Report aggregates only.
5. Fallback attempts are zero while fallback is absent. A negative non-canary check returns `404 assistant_unavailable` with zero provider-attempt delta.
6. Ready-answer leak, severe safety violation, and safe-control false fallback counts are all zero in the scheduled synthetic acceptance suite.
7. Mobile release crash and ANR test events are visible only in the production crash project, carry the expected release/environment, and contain no user, request, message, breadcrumb, token, or student data.
8. The API and Prometheus restart-persistence checks pass, daily backup age is under 36 hours, and the latest backup has a successful isolated restore rehearsal.
9. `worker_ai` remains inactive/disabled; Voice Input and TTS remain false; fallback remains absent; the cohort remains exactly one.

Passing the soak is evidence for a separate cohort-expansion decision, not authorization to expand automatically.
