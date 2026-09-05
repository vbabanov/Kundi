# Assistant one-student canary controls

This document describes configuration and verification for a future Assistant canary. It does not authorize deployment or production changes.

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

When Assistant is disabled, the existing readiness behavior is unchanged.

## No-PII observability

The canary uses the existing log-backed observability hooks. Assistant terminal outcomes are emitted once per service request through `assistant_requests_total` and `assistant_latency_ms`, with specialized counters for timeout, rate limiting, malformed responses, safety intervention, ready-answer guard, and canary denial. Speech authorization emits issuance count/latency and a rate-limit counter.

Tags are restricted to controlled values for result, error kind, provider, model, normalized locale (`ru`, `kk`, or `other`), mode, fallback use, tutoring intent, and safety category. Do not add identifiers, raw content, credentials, endpoints, provider request IDs, or free-form errors.

Log-backed metrics are sufficient for the single manual canary only. A durable metrics backend and mobile crash/ANR collection remain prerequisites for wider rollout.

## Safe activation sequence

The configuration values below are illustrative; replace the placeholder only in the approved secret/configuration system, never in source control:

```text
KUNDI_ASSISTANT_ENABLED=false
KUNDI_ASSISTANT_ROLLOUT_MODE=allowlist
KUNDI_ASSISTANT_CANARY_STUDENT_IDS=<approved-student-uuid>
```

Before any future deployment:

1. Confirm the release commit and all required CI jobs are successful.
2. Verify the approved UUID is stored only in the protected runtime configuration.
3. Verify migrations and rollback/backup prerequisites separately; this change does not apply migrations.
4. Verify observability is enabled and that logs contain no synthetic privacy markers.
5. Enable the backend master switch only through the approved production change process.
6. Exercise allowed and denied accounts, then inspect bounded outcome and latency metrics.

Rollback is to turn `KUNDI_ASSISTANT_ENABLED=false`. Do not switch to `all` as a troubleshooting shortcut.

## Wider-rollout blockers

Before moving beyond one student, resolve and verify:

- locale-specific Alem latency and routing;
- a reproducible release artifact;
- APK signing and certificate handling;
- backup/restore rehearsal;
- production secret installation;
- branch protection and manual governance;
- mobile crash/ANR collection.
