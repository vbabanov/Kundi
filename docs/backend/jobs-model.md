# Jobs / Retry / Dispatch Model (Verified)

## Storage
- `jobs`
- `job_attempts`

## Core semantics
- Lease-based pickup with `FOR UPDATE SKIP LOCKED`.
- Candidate selection includes:
  - queued and available jobs,
  - previously leased jobs with expired lease.
- Completion sets `status=succeeded` and clears lease.
- Failures increment `attempts`, record `job_attempts`, and:
  - requeue with adaptive backoff if attempts remain,
  - transition to `dead_letter` on final failure.

## Backoff
- Quadratic policy: `15 * attempt^2` seconds.
- Capped to `300s`.
- Permanent/non-retriable errors bypass retry and move directly to `dead_letter`.

## Idempotency
- Uniqueness on `(job_type, idempotency_key)`.
- Enqueue is idempotent: existing job ID is returned if duplicate key appears.

## Implemented worker baselines
- `ingest_post_processing` enqueues deterministic follow-up jobs.
- `recompute_daily_stats` executes analytics recomputation.
- `recompute_weekly_stats` executes weekly analytics recomputation.
- `generate_parent_digest` builds digest and enqueues WhatsApp dispatch.
- `dispatch_whatsapp` executes provider dispatch with dispatch-store idempotency.
- `stale_data_detection` opens/refreshes stale risk flags.
- `ai_post_processing` executes assistant policy pipeline and writes audit event.
- Worker payload parsing for dates/hours is strict and malformed payloads are treated as terminal.

## Known limitations
- Rich observability payload per attempt is still limited.
- Dead-letter operational runbook is baseline and requires production SRE tuning.
