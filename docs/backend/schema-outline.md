# Phase 3 PostgreSQL Schema Outline

## Identity and school graph
- `students`
- `student_profiles`
- `guardians`
- `guardian_contacts`
- `schools`
- `classrooms`
- `teachers`

## Diary integration and ingest
- `diary_accounts`
- `diary_source_ids`
- `ingest_batches`
- `sync_snapshots`

## Academic core
- `lessons`
- `lesson_topics`
- `homeworks`
- `homework_completions`
- `homework_photos`
- `grades`
- `summative_grades`
- `term_grades`
- `year_grades`
- `attendance_events`

## Derived analytics
- `daily_stats`
- `weekly_stats`
- `risk_flags`

## Assistant and persona
- `assistant_sessions`
- `assistant_messages`
- `persona_profiles`
- `avatar_cues`

## Dispatch and async processing
- `whatsapp_dispatches`
- `jobs`
- `job_attempts`

## Security and platform support
- `auth_refresh_sessions`
- `api_idempotency_keys`
- `audit_log`

## Constraint model
- UUID PK on all core tables.
- FK with `ON DELETE CASCADE` only where ownership is strict.
- Unique constraints for source identities and idempotency keys.
- Lease columns on jobs: `lease_owner`, `lease_until`.
- Attempt history in `job_attempts` for retry analytics and dead-letter diagnostics.
- Hardening checks:
  - snapshot/weekly date window ordering checks.
  - non-empty idempotency key checks.
  - non-negative file size checks.
  - job attempts range checks.
- Migration runner persists applied SQL files in `schema_migrations` table.
