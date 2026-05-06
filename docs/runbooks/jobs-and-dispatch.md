# Runbook: Jobs and WhatsApp Dispatch

## Scope
Operational baseline for:
- ingest post-processing jobs,
- stats recompute jobs,
- parent digest generation,
- WhatsApp dispatch jobs,
- AI post-processing jobs.

## Expected queue lifecycle
1. API or service enqueues job with `(job_type, idempotency_key)`.
2. Worker leases job.
3. Handler runs module logic.
4. On success: job is completed as `succeeded`.
5. On failure: attempts incremented, backoff applied, requeued.
6. On max attempts reached: status becomes `dead_letter`.

## Dispatch-specific checks
- Verify `whatsapp_dispatches` status transitions:
  - `pending -> sent` for success,
  - `pending -> failed` for provider failure.
- Verify duplicate sends are blocked by idempotency key.

## Dead-letter triage
- Inspect `jobs.last_error` and latest `job_attempts.error_message`.
- Confirm whether provider failure is transient or permanent.
- Requeue manually only with a **new** idempotency key after root-cause fix.

## Known operational gaps
- Per-job SLO dashboards and alerts are baseline only.
- Automatic dead-letter replay tooling is not implemented yet.
