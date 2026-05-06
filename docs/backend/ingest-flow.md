# Ingest API + Merge Flow (Verified)

## Endpoint
- `POST /v1/ingest/bundle`

## Flow
1. Validate auth context and decode canonical bundle strictly.
2. Validate source, idempotency key, bundle shape, lesson/attendance formats.
3. Normalize bundle values (source IDs, keys, grade/attendance fields).
   - `synced_at` is no longer auto-generated for checksum semantics.
4. Compute canonical checksum.
5. Create ingest batch:
   - insert if new `(student_id, idempotency_key)`,
   - detect checksum conflict for reused key with different payload.
6. Skip merge if already processed with same checksum.
7. Merge profile/source IDs/lessons/topics/homework/grades/attendance transactionally.
8. Mark batch as `merged`.

## Guarantees
- Idempotent merge per `(student_id, idempotency_key)` + checksum conflict protection.
- Backend stores canonical data only.
- Raw diary payload remains mobile connector concern.
- Merge order is deterministic (normalized + sorted + deduplicated before persistence).
- Partial updates do not erase homework/grades when source slice is intentionally absent.
- Repeated retries of the same logical payload (without explicit `synced_at`) stay idempotent.

## Known limitations
- Merge policy is deterministic but still baseline; richer conflict-resolution rules remain planned.
