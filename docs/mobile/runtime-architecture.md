# Mobile Runtime Architecture (Verified)

- State management: Riverpod.
- Local canonical cache: SQLite (`canonical_profile_cache`, `canonical_lessons_cache`, `canonical_homework_cache`, `canonical_grades_cache`, `canonical_attendance_cache`).
- Sync persistence: SQLite (`canonical_sync_queue`, `canonical_sync_metadata`) with retry metadata.
- Sensitive secrets: secure storage only (`flutter_secure_storage`).
- Connector runtime is mobile-only and source-specific.
- Feature UI consumes canonical DTOs only.
- Avatar communication uses `AvatarFacade` command/event boundary only.

## Current maturity
- Implemented:
  - SQLite v2 schema + migration path,
  - cache repositories for profile/lessons/homework/grades,
  - sync queue repository/service + Riverpod sync status provider.
  - assistant request flow (`mobile -> backend /v1/assistant/message -> avatar package -> AvatarFacade.speak`).
  - typed sync failure classification (`transient`, `auth_expired`, `conflict`, `malformed_payload`, `permanent`).
- Still partial:
  - several non-core feature modules remain decorative skeletons.
