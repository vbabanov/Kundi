# Runbook: WhatsApp Delivery Hardening

## Delivery chain
1. API enqueue (`/v1/whatsapp/send-homework` or `/send-photo`)
2. Job lease by worker
3. Dispatch payload validation
4. Provider call
5. Dispatch result persistence
6. Retry/dead-letter handling

## Hardening checklist
1. Enqueue
   - idempotency key required and stable
2. Lease
   - expired lease reclaim works
3. Dispatch
   - payload validation before provider call
4. Retry
   - transient provider failure requeued
5. Dead-letter
   - permanent malformed payload goes terminal
6. Duplicate prevention
   - repeated idempotency key does not duplicate send
7. Provider outage handling
   - retries with backoff, no tight loops

## Text and digest ownership
- Digest text generation belongs to backend domain services.
- Template/style tuning should happen in one place (digest builder/templates), not in worker loop.

## Operational checks
1. Check `jobs` status distribution (`queued`, `leased`, `dead_letter`).
2. Check `whatsapp_dispatches` statuses (`pending`, `sent`, `failed`).
3. Confirm provider-side delivery IDs are stored.
