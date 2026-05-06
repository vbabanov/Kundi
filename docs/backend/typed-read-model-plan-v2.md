# Typed Backend Read Plan v2 (Phase 3)

## Endpoint boundaries
- `GET /v2/profile`
  - returns only:
    - `window`
    - `provider_identity`
    - `local_app_profile`
  - no lessons/results/aggregates payload.
- `GET /v2/results`
  - returns windowed typed collections:
    - `lessons`
    - `results` (event-level: `regular|sor|soch`)
    - `aggregates` (`term|year`)
    - `attendance`
  - no profile merge in this endpoint.
- `GET /v2/academic/overview`
  - compact read projection:
    - `window`
    - `provider_identity`
    - `local_app_profile`
    - `counts`
    - `highlights`
  - not a mega-endpoint for all domain data.

## Window and snapshot semantics
- `window` fields:
  - `provider`
  - `window_from` (`YYYY-MM-DD`)
  - `window_to` (`YYYY-MM-DD`)
  - `snapshot_at` (`RFC3339`)
  - `window_key` (`provider:window_from:window_to`)
- defaults (if query absent):
  - `window_from = now-30d`
  - `window_to = now+14d`
- stale row definition for mobile cache:
  - same `window_key` but `snapshot_at != active_snapshot_at`.
  - stale rows are cleaned during v2 refresh write.

## Highlights selection rules
`/v2/academic/overview.highlights` is read projection only.

- `recent_results`
  - source: `academic_results`
  - selection: inside window
  - order: `recorded_on desc, updated_at desc`
  - limit: `5`
- `upcoming_lessons`
  - source: `lessons + lesson_topics + homeworks`
  - selection: `lesson_date >= snapshot_at::date` and inside window
  - order: `lesson_date asc, lesson_number asc`
  - limit: `8`

No hidden business rules or write-side mutations are executed in highlights.

## v1/v2 parity contract
- Must match between v1 and v2:
  - provider-derived identity values (`school`, `class`, `teacher`, student name)
  - grade counts for overlapping window
  - mood preservation (`resolved_mood` in v2, mapped to legacy mood field in compatibility cache)
- Allowed differences:
  - field names and DTO nesting
  - explicit split (`provider_identity` vs `local_app_profile`) in v2
  - overview highlights limits
- Considered bug:
  - missing provider in v2 facts
  - cross-kind merge leak (`regular` vs `sor/soch`)
  - profile/local-app-profile mixing.

## Backward compatibility
- `v1` endpoints remain unchanged.
- `v2` read endpoints are additive.
- mobile rollout uses feature flag `USE_TYPED_V2_READ`; default remains `false`.
