# Runbook: Dead-Letter Replay

## Purpose
Safely replay failed jobs after root-cause fix.

## Before replay
1. Identify reason in:
   - `jobs.last_error`
   - `job_attempts.error_message`
2. Classify failure:
   - transient outage (safe replay)
   - malformed payload (fix payload first)
   - auth/secret issue (fix configuration first)

## Replay rules
1. Never mutate old idempotency key in-place.
2. Create a new job with new idempotency key.
3. Keep payload trace linked to old failed job ID in audit metadata.

## Manual replay checklist
1. Confirm provider health is restored.
2. Generate replay payload with validated format.
3. Enqueue replay job.
4. Watch lease + completion path.
5. Verify dispatch status is `sent`.

## Do-not
- Do not bulk replay dead-letter jobs blindly.
- Do not replay malformed payloads without parser/template fix.
